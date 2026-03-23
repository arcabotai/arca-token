// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title ArcaPresaleV2
 * @notice Presale contract for $ARCA token on Base
 * @dev ETH collection with soft/hard caps, OG whitelist bonus, and Safe vault forwarding
 * 
 * Flow:
 * 1. Presale opens — anyone can contribute (min 0.01 ETH, max 1 ETH per wallet)
 * 2. All ETH is immediately forwarded to a Gnosis Safe multisig vault
 * 3. Soft cap (5 ETH) — no time limit, presale stays open until hit
 * 4. Once soft cap is hit, hard cap phase begins (5 day timer)
 * 5. Hard cap (12.5 ETH) or timer expires → presale closes
 * 6. 26 OG wallets from previous presale get 10% bonus token allocation
 * 
 * Security improvements over V1:
 * - ETH forwarded immediately to Safe (no funds held in contract)
 * - Owner = Gnosis Safe (2-of-2 multisig required for admin actions)
 * - Partial fill at hard cap (excess ETH returned, not reverted)
 * - ERC-20 rescue function for accidentally sent tokens
 * - No refund mechanism needed (contract balance always 0)
 */
contract ArcaPresaleV2 {
    // ─── State ───────────────────────────────────────────────────────
    address public immutable owner; // Should be the Gnosis Safe itself
    address payable public immutable vault; // Gnosis Safe multisig
    uint256 public immutable softCap;
    uint256 public immutable hardCap;
    uint256 public immutable minContribution;
    uint256 public immutable maxContribution;
    uint256 public immutable hardCapDuration; // seconds after soft cap hit
    uint256 public immutable ogBonusBps; // 1000 = 10%

    uint256 public totalRaised;
    bool public presaleClosed;
    uint256 public softCapReachedAt; // timestamp when soft cap was hit (0 = not yet)
    
    mapping(address => uint256) public contributions;
    mapping(address => bool) public ogWhitelist;
    address[] public contributors;

    // ─── Events ──────────────────────────────────────────────────────
    event Contributed(address indexed contributor, uint256 amount, uint256 totalContribution, bool isOG);
    event PartialFill(address indexed contributor, uint256 accepted, uint256 returned);
    event SoftCapReached(uint256 timestamp, uint256 totalRaised);
    event HardCapReached(uint256 timestamp, uint256 totalRaised);
    event PresaleClosed(uint256 timestamp, uint256 totalRaised, uint256 numContributors);
    event OGWhitelisted(address indexed wallet);
    event VaultForwarded(uint256 amount);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    // ─── Errors ──────────────────────────────────────────────────────
    error PresaleNotActive();
    error BelowMinimum();
    error AboveMaximum();
    error OnlyOwner();
    error AlreadyClosed();
    error RescueFailed();

    // ─── Constructor ─────────────────────────────────────────────────
    /// @param _vault Gnosis Safe address (also recommended as msg.sender/owner for max trust)
    /// @param _ogWallets Array of 26 OG contributor addresses
    constructor(
        address payable _vault,
        address[] memory _ogWallets
    ) {
        owner = msg.sender; // Deploy from Safe for maximum trust, or set to Safe address
        vault = _vault;
        softCap = 5 ether;
        hardCap = 12.5 ether;
        minContribution = 0.01 ether;
        maxContribution = 1 ether;
        hardCapDuration = 5 days;
        ogBonusBps = 1000; // 10%

        // Whitelist OG contributors
        for (uint256 i = 0; i < _ogWallets.length; i++) {
            ogWhitelist[_ogWallets[i]] = true;
            emit OGWhitelisted(_ogWallets[i]);
        }
    }

    // ─── Contribute ──────────────────────────────────────────────────
    receive() external payable {
        contribute();
    }

    function contribute() public payable {
        if (presaleClosed) revert PresaleNotActive();
        if (_isHardCapPhaseExpired()) revert PresaleNotActive();
        if (msg.value < minContribution) revert BelowMinimum();
        if (contributions[msg.sender] + msg.value > maxContribution) revert AboveMaximum();

        uint256 accepted = msg.value;
        uint256 returned = 0;

        // Partial fill: if contribution would exceed hard cap, accept only what fits
        if (totalRaised + accepted > hardCap) {
            accepted = hardCap - totalRaised;
            returned = msg.value - accepted;
        }

        // Track contribution
        if (contributions[msg.sender] == 0) {
            contributors.push(msg.sender);
        }
        contributions[msg.sender] += accepted;
        totalRaised += accepted;

        // Forward accepted ETH to vault immediately
        (bool sent,) = vault.call{value: accepted}("");
        require(sent, "Vault transfer failed");
        emit VaultForwarded(accepted);

        // Return excess ETH if partial fill
        if (returned > 0) {
            (bool refunded,) = payable(msg.sender).call{value: returned}("");
            require(refunded, "Refund of excess failed");
            emit PartialFill(msg.sender, accepted, returned);
        }

        bool isOGContributor = ogWhitelist[msg.sender];
        emit Contributed(msg.sender, accepted, contributions[msg.sender], isOGContributor);

        // Check milestones
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

    // ─── Close presale (owner only — should be multisig) ─────────────
    function closePresale() external {
        if (presaleClosed) revert AlreadyClosed();
        // Only owner (multisig) or anyone after timer expires
        if (msg.sender != owner && !_isHardCapPhaseExpired()) revert OnlyOwner();
        
        presaleClosed = true;
        emit PresaleClosed(block.timestamp, totalRaised, contributors.length);
    }

    // ─── Rescue accidentally sent ERC-20 tokens ──────────────────────
    /// @notice Recover ERC-20 tokens accidentally sent to this contract
    /// @param token The ERC-20 token address
    /// @param to Where to send the rescued tokens (should be the contributor)
    /// @param amount Amount to rescue
    function rescueTokens(address token, address to, uint256 amount) external {
        if (msg.sender != owner) revert OnlyOwner();
        bool success = IERC20(token).transfer(to, amount);
        if (!success) revert RescueFailed();
        emit TokensRescued(token, to, amount);
    }

    // ─── Views ───────────────────────────────────────────────────────
    function isActive() public view returns (bool) {
        return !presaleClosed && !_isHardCapPhaseExpired();
    }

    function isOG(address wallet) public view returns (bool) {
        return ogWhitelist[wallet];
    }

    function getContribution(address wallet) public view returns (uint256) {
        return contributions[wallet];
    }

    /// @notice Get token allocation weight (contribution + OG bonus)
    function getAllocationWeight(address wallet) public view returns (uint256) {
        uint256 base = contributions[wallet];
        if (ogWhitelist[wallet] && base > 0) {
            return base + (base * ogBonusBps / 10000);
        }
        return base;
    }

    function getContributorCount() public view returns (uint256) {
        return contributors.length;
    }

    function getContributorAt(uint256 index) public view returns (address) {
        return contributors[index];
    }

    function hardCapDeadline() public view returns (uint256) {
        if (softCapReachedAt == 0) return 0; // no deadline yet
        return softCapReachedAt + hardCapDuration;
    }

    function timeRemaining() public view returns (uint256) {
        uint256 deadline = hardCapDeadline();
        if (deadline == 0) return type(uint256).max; // no timer active
        if (block.timestamp >= deadline) return 0;
        return deadline - block.timestamp;
    }

    /// @notice Get remaining ETH capacity before hard cap
    function remainingCapacity() public view returns (uint256) {
        if (totalRaised >= hardCap) return 0;
        return hardCap - totalRaised;
    }

    // ─── Internal ────────────────────────────────────────────────────
    function _isHardCapPhaseExpired() internal view returns (bool) {
        if (softCapReachedAt == 0) return false; // soft cap not hit, no timer
        return block.timestamp >= softCapReachedAt + hardCapDuration;
    }

    // ─── Get all contributors + amounts (for airdrop calculation) ────
    function getAllContributions() external view returns (
        address[] memory wallets,
        uint256[] memory amounts,
        uint256[] memory weights,
        bool[] memory isOGList
    ) {
        uint256 len = contributors.length;
        wallets = new address[](len);
        amounts = new uint256[](len);
        weights = new uint256[](len);
        isOGList = new bool[](len);

        for (uint256 i = 0; i < len; i++) {
            wallets[i] = contributors[i];
            amounts[i] = contributions[contributors[i]];
            weights[i] = getAllocationWeight(contributors[i]);
            isOGList[i] = ogWhitelist[contributors[i]];
        }
    }
}
