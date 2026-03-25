// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title ArcaPresaleV3
 * @author Arca (arcabot.eth) + Felipe (@felirami)
 * @notice Bonding curve presale for $ARCA on Base
 *
 * @dev Snapshot-weighted allocation: early contributors get up to 1.5x more tokens.
 *
 * How it works:
 *   1. Anyone sends ETH (0.01–1 ETH per wallet).
 *   2. ETH forwards immediately to the Gnosis Safe vault.
 *   3. The contract records totalRaised at the moment of each contribution.
 *   4. Token allocation weight = amount × multiplier(totalRaised_at_time).
 *   5. Multiplier decays quadratically: 1.5× for the first wei, 1.0× at hard cap.
 *
 * Multiplier formula (basis points):
 *   m = MAX_MULT - (MAX_MULT - MIN_MULT) × (raised / hardCap)²
 *   MAX_MULT = 15000 (1.5×)  MIN_MULT = 10000 (1.0×)
 *
 * OG wallets from the V1 presale get an additional 10% bonus on top.
 *
 * Security:
 *   - Zero ETH held in contract (immediate vault forwarding)
 *   - No unbounded loops in write functions (O(1) contributions)
 *   - Checks-effects-interactions pattern
 *   - Partial fill at hard cap (excess returned)
 *   - ERC-20 rescue for accidental token transfers
 *   - startTime gate prevents contributions before launch
 *   - Fully verified on BaseScan
 */
contract ArcaPresaleV3 {
    // ─── Constants ───────────────────────────────────────────────────
    uint256 public constant MAX_MULT = 15000;   // 1.5× in bps
    uint256 public constant MIN_MULT = 10000;   // 1.0× in bps
    uint256 public constant BPS = 10000;
    uint256 public constant OG_BONUS_BPS = 1000; // 10%

    // ─── Immutables ──────────────────────────────────────────────────
    address public immutable owner;
    address payable public immutable vault;
    uint256 public immutable softCap;
    uint256 public immutable hardCap;
    uint256 public immutable minContribution;
    uint256 public immutable maxContribution;
    uint256 public immutable hardCapDuration;
    uint256 public immutable startTime;

    // ─── State ───────────────────────────────────────────────────────
    uint256 public totalRaised;
    bool    public presaleClosed;
    uint256 public softCapReachedAt;

    /// @dev Each contribution stores amount + snapshot of totalRaised for multiplier calc
    struct Contribution {
        uint128 amount;
        uint128 totalRaisedSnapshot;
    }

    mapping(address => Contribution[]) internal _contributions;
    mapping(address => uint256) public totalContributed;
    mapping(address => bool)    public ogWhitelist;
    address[] public contributors;

    // ─── Events ──────────────────────────────────────────────────────
    event Contributed(
        address indexed contributor,
        uint256 amount,
        uint256 totalContribution,
        uint256 multiplierBps,
        bool    isOG,
        uint256 position
    );
    event PartialFill(address indexed contributor, uint256 accepted, uint256 returned);
    event SoftCapReached(uint256 timestamp, uint256 totalRaised);
    event HardCapReached(uint256 timestamp, uint256 totalRaised);
    event PresaleClosed(uint256 timestamp, uint256 totalRaised, uint256 numContributors);
    event OGWhitelisted(address indexed wallet);
    event VaultForwarded(uint256 amount);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    // ─── Errors ──────────────────────────────────────────────────────
    error NotStarted();
    error PresaleNotActive();
    error BelowMinimum();
    error AboveMaximum();
    error OnlyOwner();
    error AlreadyClosed();
    error RescueFailed();

    // ─── Constructor ─────────────────────────────────────────────────
    constructor(
        uint256        _startTime,
        address payable _vault,
        address[] memory _ogWallets
    ) {
        owner           = msg.sender;
        vault           = _vault;
        softCap         = 5 ether;
        hardCap         = 12.5 ether;
        minContribution = 0.01 ether;
        maxContribution = 1 ether;
        hardCapDuration = 5 days;
        startTime       = _startTime;

        for (uint256 i; i < _ogWallets.length; ++i) {
            ogWhitelist[_ogWallets[i]] = true;
            emit OGWhitelisted(_ogWallets[i]);
        }
    }

    // ─── Contribute ──────────────────────────────────────────────────
    receive() external payable { contribute(); }

    function contribute() public payable {
        if (block.timestamp < startTime) revert NotStarted();
        if (presaleClosed) revert PresaleNotActive();
        if (_isHardCapPhaseExpired()) revert PresaleNotActive();
        if (msg.value < minContribution) revert BelowMinimum();
        if (totalContributed[msg.sender] + msg.value > maxContribution) revert AboveMaximum();

        uint256 accepted = msg.value;
        uint256 returned;

        // Partial fill at cap
        if (totalRaised + accepted > hardCap) {
            accepted = hardCap - totalRaised;
            returned = msg.value - accepted;
        }

        // Record contributor (first time only)
        uint256 position;
        if (totalContributed[msg.sender] == 0) {
            contributors.push(msg.sender);
        }
        position = contributors.length; // current position count

        // Snapshot the multiplier at THIS moment
        uint256 snapshotRaised = totalRaised;

        // Update state
        _contributions[msg.sender].push(Contribution({
            amount: uint128(accepted),
            totalRaisedSnapshot: uint128(snapshotRaised)
        }));
        totalContributed[msg.sender] += accepted;
        totalRaised += accepted;

        // Forward to vault
        (bool sent, ) = vault.call{value: accepted}("");
        require(sent, "Vault transfer failed");
        emit VaultForwarded(accepted);

        // Return excess
        if (returned > 0) {
            (bool refunded, ) = payable(msg.sender).call{value: returned}("");
            require(refunded, "Excess refund failed");
            emit PartialFill(msg.sender, accepted, returned);
        }

        // Emit with multiplier info
        uint256 mult = _multiplierAtRaised(snapshotRaised);
        emit Contributed(msg.sender, accepted, totalContributed[msg.sender], mult, ogWhitelist[msg.sender], position);

        // Milestones
        if (softCapReachedAt == 0 && totalRaised >= softCap) {
            softCapReachedAt = block.timestamp;
            emit SoftCapReached(block.timestamp, totalRaised);
        }
        if (totalRaised >= hardCap) {
            presaleClosed = true;
            emit HardCapReached(block.timestamp, totalRaised);
            emit PresaleClosed(block.timestamp, totalRaised, contributors.length);
        }
    }

    // ─── Multiplier ──────────────────────────────────────────────────

    /// @notice Compute the multiplier for a contribution made when totalRaised was `raised`
    /// @return Multiplier in basis points (15000 = 1.5×, 10000 = 1.0×)
    function _multiplierAtRaised(uint256 raised) internal view returns (uint256) {
        if (raised >= hardCap) return MIN_MULT;
        // m = MAX_MULT - (MAX_MULT - MIN_MULT) × (raised / hardCap)²
        // Using BPS precision: multiply first, divide last to avoid truncation
        uint256 ratio = (raised * BPS) / hardCap;          // 0..10000
        uint256 ratioSq = (ratio * ratio) / BPS;           // 0..10000 (squared, scaled back)
        uint256 decay = ((MAX_MULT - MIN_MULT) * ratioSq) / BPS;
        return MAX_MULT - decay;
    }

    /// @notice Get the current multiplier (what a new contributor would get right now)
    function currentMultiplier() external view returns (uint256) {
        return _multiplierAtRaised(totalRaised);
    }

    /// @notice Get the current price ratio as a human-readable string hint
    /// @return bps Multiplier in basis points
    /// @return label "1.50x" style label
    function currentPriceInfo() external view returns (uint256 bps, string memory label) {
        bps = _multiplierAtRaised(totalRaised);
        // Simple label: bps / 100 with one decimal
        uint256 whole = bps / BPS;
        uint256 frac = (bps % BPS) / 1000; // first decimal
        label = string(abi.encodePacked(
            _toString(whole), ".", _toString(frac), "x"
        ));
    }

    // ─── Allocation Weight ───────────────────────────────────────────

    /// @notice Total allocation weight for a wallet (sum of each contribution × its multiplier + OG bonus)
    function getAllocationWeight(address wallet) public view returns (uint256 weight) {
        Contribution[] storage contribs = _contributions[wallet];
        for (uint256 i; i < contribs.length; ++i) {
            uint256 mult = _multiplierAtRaised(contribs[i].totalRaisedSnapshot);
            weight += (uint256(contribs[i].amount) * mult) / BPS;
        }
        // OG bonus on top
        if (ogWhitelist[wallet] && weight > 0) {
            weight += (weight * OG_BONUS_BPS) / BPS;
        }
    }

    // ─── Admin ───────────────────────────────────────────────────────

    function closePresale() external {
        if (presaleClosed) revert AlreadyClosed();
        if (msg.sender != owner && !_isHardCapPhaseExpired()) revert OnlyOwner();
        presaleClosed = true;
        emit PresaleClosed(block.timestamp, totalRaised, contributors.length);
    }

    function rescueTokens(address token, address to, uint256 amount) external {
        if (msg.sender != owner) revert OnlyOwner();
        if (!IERC20(token).transfer(to, amount)) revert RescueFailed();
        emit TokensRescued(token, to, amount);
    }

    // ─── Views ───────────────────────────────────────────────────────

    function isStarted() public view returns (bool) { return block.timestamp >= startTime; }

    function isActive() public view returns (bool) {
        return block.timestamp >= startTime && !presaleClosed && !_isHardCapPhaseExpired();
    }

    function isOG(address wallet) external view returns (bool) { return ogWhitelist[wallet]; }

    function getContribution(address wallet) external view returns (uint256) { return totalContributed[wallet]; }

    function getContributorCount() external view returns (uint256) { return contributors.length; }

    function getContributorAt(uint256 index) external view returns (address) { return contributors[index]; }

    function remainingCapacity() public view returns (uint256) {
        return totalRaised >= hardCap ? 0 : hardCap - totalRaised;
    }

    function hardCapDeadline() public view returns (uint256) {
        return softCapReachedAt == 0 ? 0 : softCapReachedAt + hardCapDuration;
    }

    function timeRemaining() external view returns (uint256) {
        uint256 deadline = hardCapDeadline();
        if (deadline == 0) return type(uint256).max;
        return block.timestamp >= deadline ? 0 : deadline - block.timestamp;
    }

    /// @notice Get detailed contribution data for airdrop calculation
    function getAllContributions() external view returns (
        address[] memory wallets,
        uint256[] memory amounts,
        uint256[] memory weights,
        uint256[] memory multipliers,
        bool[]    memory isOGList
    ) {
        uint256 len = contributors.length;
        wallets     = new address[](len);
        amounts     = new uint256[](len);
        weights     = new uint256[](len);
        multipliers = new uint256[](len);
        isOGList    = new bool[](len);

        for (uint256 i; i < len; ++i) {
            address w = contributors[i];
            wallets[i]     = w;
            amounts[i]     = totalContributed[w];
            weights[i]     = getAllocationWeight(w);
            isOGList[i]    = ogWhitelist[w];
            // Average multiplier across all contributions
            Contribution[] storage c = _contributions[w];
            uint256 totalMult;
            for (uint256 j; j < c.length; ++j) {
                totalMult += _multiplierAtRaised(c[j].totalRaisedSnapshot);
            }
            multipliers[i] = c.length > 0 ? totalMult / c.length : BPS;
        }
    }

    /// @notice Get a wallet's individual contributions (for NFT rendering)
    function getContributionDetails(address wallet) external view returns (
        uint256[] memory amounts,
        uint256[] memory snapshots,
        uint256[] memory mults
    ) {
        Contribution[] storage c = _contributions[wallet];
        uint256 len = c.length;
        amounts   = new uint256[](len);
        snapshots = new uint256[](len);
        mults     = new uint256[](len);
        for (uint256 i; i < len; ++i) {
            amounts[i]   = c[i].amount;
            snapshots[i] = c[i].totalRaisedSnapshot;
            mults[i]     = _multiplierAtRaised(c[i].totalRaisedSnapshot);
        }
    }

    // ─── Internal ────────────────────────────────────────────────────

    function _isHardCapPhaseExpired() internal view returns (bool) {
        return softCapReachedAt != 0 && block.timestamp >= softCapReachedAt + hardCapDuration;
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
        return string(buffer);
    }
}
