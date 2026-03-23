// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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
 * Key differences from V1:
 * - ETH forwarded immediately to Safe (no funds held in contract)
 * - No time limit before soft cap
 * - Hard cap phase has 5-day timer (starts when soft cap hit)
 * - OG whitelist for bonus (not time-based early bird)
 * - No refund mechanism (funds go to multisig immediately)
 */
contract ArcaPresaleV2 {
    // ─── State ───────────────────────────────────────────────────────
    address public immutable owner;
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
    event SoftCapReached(uint256 timestamp, uint256 totalRaised);
    event HardCapReached(uint256 timestamp, uint256 totalRaised);
    event PresaleClosed(uint256 timestamp, uint256 totalRaised, uint256 numContributors);
    event OGWhitelisted(address indexed wallet);
    event VaultForwarded(uint256 amount);

    // ─── Errors ──────────────────────────────────────────────────────
    error PresaleNotActive();
    error BelowMinimum();
    error AboveMaximum();
    error HardCapExceeded();
    error OnlyOwner();
    error AlreadyClosed();

    // ─── Constructor ─────────────────────────────────────────────────
    constructor(
        address payable _vault,
        address[] memory _ogWallets
    ) {
        owner = msg.sender;
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
        if (totalRaised + msg.value > hardCap) revert HardCapExceeded();

        // Track contribution
        if (contributions[msg.sender] == 0) {
            contributors.push(msg.sender);
        }
        contributions[msg.sender] += msg.value;
        totalRaised += msg.value;

        // Forward ETH to vault immediately
        (bool sent,) = vault.call{value: msg.value}("");
        require(sent, "Vault transfer failed");
        emit VaultForwarded(msg.value);

        bool isOG = ogWhitelist[msg.sender];
        emit Contributed(msg.sender, msg.value, contributions[msg.sender], isOG);

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

    // ─── Close presale (owner or anyone after timer) ─────────────────
    function closePresale() external {
        if (presaleClosed) revert AlreadyClosed();
        if (msg.sender != owner && !_isHardCapPhaseExpired()) revert OnlyOwner();
        
        presaleClosed = true;
        emit PresaleClosed(block.timestamp, totalRaised, contributors.length);
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
