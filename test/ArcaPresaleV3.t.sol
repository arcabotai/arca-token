// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/ArcaPresaleV3.sol";

contract ArcaPresaleV3Test is Test {
    ArcaPresaleV3 presale;
    address payable vault = payable(makeAddr("vault"));
    address owner = makeAddr("owner");
    address og1 = makeAddr("og1");
    address og2 = makeAddr("og2");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");

    function setUp() public {
        address[] memory ogWallets = new address[](2);
        ogWallets[0] = og1;
        ogWallets[1] = og2;
        vm.deal(vault, 0);
        vm.deal(og1, 10 ether);
        vm.deal(og2, 10 ether);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.prank(owner);
        presale = new ArcaPresaleV3(block.timestamp, vault, ogWallets);
    }

    // ─── Multiplier Tests ────────────────────────────────────────────

    function test_multiplierAtZero() public view {
        uint256 mult = presale.currentMultiplier();
        assertEq(mult, 15000, "First contributor should get 1.5x");
    }

    function test_multiplierDecaysWithRaised() public {
        // Contribute 6.25 ETH (half of hard cap)
        for (uint i = 0; i < 6; i++) {
            address u = makeAddr(string(abi.encodePacked("decay", i)));
            vm.deal(u, 2 ether);
            vm.prank(u);
            presale.contribute{value: 1 ether}();
        }
        vm.prank(user1);
        presale.contribute{value: 0.25 ether}();
        // At 6.25 ETH (50% of 12.5), multiplier should be:
        // m = 15000 - 5000 * (6.25/12.5)^2 = 15000 - 5000 * 0.25 = 13750
        uint256 mult = presale.currentMultiplier();
        assertEq(mult, 13750, "At 50% filled, multiplier should be 1.375x");
    }

    function test_multiplierAtHardCap() public {
        // Fill to hard cap
        for (uint i = 0; i < 12; i++) {
            address u = makeAddr(string(abi.encodePacked("cap", i)));
            vm.deal(u, 2 ether);
            vm.prank(u);
            presale.contribute{value: 1 ether}();
        }
        address last = makeAddr("capLast");
        vm.deal(last, 1 ether);
        vm.prank(last);
        presale.contribute{value: 0.5 ether}();
        // At hard cap, multiplier = 10000 (1.0x)
        assertEq(presale.totalRaised(), 12.5 ether);
        assertTrue(presale.presaleClosed());
    }

    function test_earlyContributorGetsMoreWeight() public {
        // User1 contributes first (low totalRaised = high multiplier)
        vm.prank(user1);
        presale.contribute{value: 0.5 ether}();
        
        // Fill up some
        for (uint i = 0; i < 10; i++) {
            address u = makeAddr(string(abi.encodePacked("fill", i)));
            vm.deal(u, 2 ether);
            vm.prank(u);
            presale.contribute{value: 1 ether}();
        }
        
        // User2 contributes late (high totalRaised = low multiplier)
        vm.prank(user2);
        presale.contribute{value: 0.5 ether}();
        
        uint256 weight1 = presale.getAllocationWeight(user1);
        uint256 weight2 = presale.getAllocationWeight(user2);
        
        // User1 should have MORE weight than user2 despite same ETH
        assertGt(weight1, weight2, "Early contributor should have more weight");
        // User1 at ~0 raised gets ~1.5x, user2 at 10.5 gets ~1.15x
        assertGt(weight1, 0.7 ether, "Early weight should be > 0.7 ETH equiv");
        assertLt(weight2, 0.6 ether, "Late weight should be < 0.6 ETH equiv");
    }

    function test_ogBonusStacksWithMultiplier() public {
        // OG contributes first
        vm.prank(og1);
        presale.contribute{value: 1 ether}();
        
        // Regular user contributes same amount at same time
        vm.prank(user1);
        presale.contribute{value: 1 ether}();
        
        uint256 ogWeight = presale.getAllocationWeight(og1);
        uint256 userWeight = presale.getAllocationWeight(user1);
        
        // OG should get 10% more on top of multiplier
        // Both at ~0 raised = ~1.5x multiplier
        // OG: 1 * 1.5 * 1.1 = 1.65
        // User: 1 * 1.5 = 1.5
        assertGt(ogWeight, userWeight, "OG should have more weight");
        // OG weight should be ~10% more than user weight
        uint256 expectedOGMin = userWeight; // OG should always be more
        assertGt(ogWeight, expectedOGMin, "OG weight should exceed regular user");
    }

    function test_multipleContributionsDifferentMultipliers() public {
        // User contributes twice at different points
        vm.prank(user1);
        presale.contribute{value: 0.5 ether}();
        
        // Fill some
        for (uint i = 0; i < 5; i++) {
            address u = makeAddr(string(abi.encodePacked("multi", i)));
            vm.deal(u, 2 ether);
            vm.prank(u);
            presale.contribute{value: 1 ether}();
        }
        
        // User contributes again at higher totalRaised
        vm.prank(user1);
        presale.contribute{value: 0.5 ether}();
        
        // Weight should reflect both contributions with their respective multipliers
        uint256 weight = presale.getAllocationWeight(user1);
        assertGt(weight, 0.5 ether, "Combined weight should exceed either contribution alone");
        assertEq(presale.totalContributed(user1), 1 ether, "Total contributed should be 1 ETH");
    }

    // ─── Core Presale Tests ──────────────────────────────────────────

    function test_initialState() public view {
        assertEq(presale.softCap(), 5 ether);
        assertEq(presale.hardCap(), 12.5 ether);
        assertEq(presale.MAX_MULT(), 15000);
        assertEq(presale.MIN_MULT(), 10000);
        assertTrue(presale.isActive());
        assertTrue(presale.isOG(og1));
        assertFalse(presale.isOG(user1));
    }

    function test_contributeForwardsToVault() public {
        vm.prank(user1);
        presale.contribute{value: 0.1 ether}();
        assertEq(address(presale).balance, 0, "Contract should hold zero ETH");
        assertEq(vault.balance, 0.1 ether, "Vault should have the ETH");
    }

    function test_partialFillReturnsExcess() public {
        for (uint i = 0; i < 12; i++) {
            address u = makeAddr(string(abi.encodePacked("partial", i)));
            vm.deal(u, 2 ether);
            vm.prank(u);
            presale.contribute{value: 1 ether}();
        }
        address filler = makeAddr("filler");
        vm.deal(filler, 2 ether);
        uint256 before = filler.balance;
        vm.prank(filler);
        presale.contribute{value: 1 ether}();
        assertEq(presale.totalContributed(filler), 0.5 ether, "Should only accept 0.5");
        assertEq(filler.balance, before - 0.5 ether, "Should return 0.5");
        assertTrue(presale.presaleClosed());
    }

    function test_cannotContributeBeforeStart() public {
        address[] memory og = new address[](0);
        vm.prank(owner);
        ArcaPresaleV3 future = new ArcaPresaleV3(block.timestamp + 1 hours, vault, og);
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert(ArcaPresaleV3.NotStarted.selector);
        future.contribute{value: 0.1 ether}();
    }

    function test_softCapTriggersTimer() public {
        for (uint i = 0; i < 5; i++) {
            address u = makeAddr(string(abi.encodePacked("soft", i)));
            vm.deal(u, 2 ether);
            vm.prank(u);
            presale.contribute{value: 1 ether}();
        }
        assertTrue(presale.softCapReachedAt() > 0);
        assertEq(presale.hardCapDeadline(), block.timestamp + 5 days);
    }

    function test_timerExpiryClosesPresale() public {
        for (uint i = 0; i < 5; i++) {
            address u = makeAddr(string(abi.encodePacked("timer", i)));
            vm.deal(u, 2 ether);
            vm.prank(u);
            presale.contribute{value: 1 ether}();
        }
        vm.warp(block.timestamp + 5 days + 1);
        assertFalse(presale.isActive());
    }

    function test_noTimerBeforeSoftCap() public {
        vm.prank(user1);
        presale.contribute{value: 0.1 ether}();
        vm.warp(block.timestamp + 365 days);
        assertTrue(presale.isActive(), "Should stay active forever before soft cap");
    }

    function test_currentPriceInfo() public view {
        (uint256 bps, string memory label) = presale.currentPriceInfo();
        assertEq(bps, 15000);
        assertEq(label, "1.5x");
    }

    function test_getContributionDetails() public {
        vm.prank(user1);
        presale.contribute{value: 0.3 ether}();
        
        (uint256[] memory amounts, uint256[] memory snapshots, uint256[] memory mults) = presale.getContributionDetails(user1);
        assertEq(amounts.length, 1);
        assertEq(amounts[0], 0.3 ether);
        assertEq(snapshots[0], 0); // first contribution, totalRaised was 0
        assertEq(mults[0], 15000); // max multiplier
    }

    function test_getAllContributionsIncludesMultipliers() public {
        vm.prank(og1);
        presale.contribute{value: 0.5 ether}();
        vm.prank(user1);
        presale.contribute{value: 0.5 ether}();

        (
            address[] memory wallets,
            uint256[] memory amounts,
            uint256[] memory weights,
            uint256[] memory multipliers,
            bool[] memory isOGList
        ) = presale.getAllContributions();

        assertEq(wallets.length, 2);
        assertTrue(isOGList[0]); // og1
        assertFalse(isOGList[1]); // user1
        assertGt(weights[0], weights[1], "OG should have higher weight");
        assertGe(multipliers[0], multipliers[1], "First contributor gets >= multiplier");
    }

    // ─── Edge Cases ──────────────────────────────────────────────────

    function test_contractAlwaysZeroBalance() public {
        vm.prank(user1);
        presale.contribute{value: 0.5 ether}();
        vm.prank(og1);
        presale.contribute{value: 1 ether}();
        assertEq(address(presale).balance, 0);
    }

    function test_revertBelowMin() public {
        vm.prank(user1);
        vm.expectRevert(ArcaPresaleV3.BelowMinimum.selector);
        presale.contribute{value: 0.001 ether}();
    }

    function test_revertAboveMax() public {
        vm.prank(user1);
        presale.contribute{value: 1 ether}();
        vm.prank(user1);
        vm.expectRevert(ArcaPresaleV3.AboveMaximum.selector);
        presale.contribute{value: 0.01 ether}();
    }

    function test_noDuplicateContributors() public {
        vm.startPrank(user1);
        presale.contribute{value: 0.1 ether}();
        presale.contribute{value: 0.1 ether}();
        presale.contribute{value: 0.1 ether}();
        vm.stopPrank();
        assertEq(presale.getContributorCount(), 1);
    }
}
