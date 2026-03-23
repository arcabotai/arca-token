// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/ArcaPresaleV2.sol";

contract ArcaPresaleV2Test is Test {
    ArcaPresaleV2 presale;
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
        presale = new ArcaPresaleV2(vault, ogWallets);
    }

    function test_initialState() public view {
        assertEq(presale.softCap(), 5 ether);
        assertEq(presale.hardCap(), 12.5 ether);
        assertEq(presale.minContribution(), 0.01 ether);
        assertEq(presale.maxContribution(), 1 ether);
        assertEq(presale.totalRaised(), 0);
        assertFalse(presale.presaleClosed());
        assertTrue(presale.isActive());
        assertTrue(presale.isOG(og1));
        assertTrue(presale.isOG(og2));
        assertFalse(presale.isOG(user1));
    }

    function test_contribute() public {
        vm.prank(user1);
        presale.contribute{value: 0.1 ether}();

        assertEq(presale.contributions(user1), 0.1 ether);
        assertEq(presale.totalRaised(), 0.1 ether);
        assertEq(vault.balance, 0.1 ether); // forwarded immediately
        assertEq(presale.getContributorCount(), 1);
    }

    function test_contributeViaReceive() public {
        vm.prank(user1);
        (bool ok,) = address(presale).call{value: 0.1 ether}("");
        assertTrue(ok);
        assertEq(presale.totalRaised(), 0.1 ether);
    }

    function test_ogBonus() public {
        vm.prank(og1);
        presale.contribute{value: 1 ether}();

        // OG gets 10% bonus weight
        assertEq(presale.getAllocationWeight(og1), 1.1 ether);
        // Regular user gets 1:1
        vm.prank(user1);
        presale.contribute{value: 1 ether}();
        assertEq(presale.getAllocationWeight(user1), 1 ether);
    }

    function test_revertBelowMin() public {
        vm.prank(user1);
        vm.expectRevert(ArcaPresaleV2.BelowMinimum.selector);
        presale.contribute{value: 0.001 ether}();
    }

    function test_revertAboveMax() public {
        vm.prank(user1);
        presale.contribute{value: 1 ether}();
        
        vm.prank(user1);
        vm.expectRevert(ArcaPresaleV2.AboveMaximum.selector);
        presale.contribute{value: 0.01 ether}();
    }

    function test_softCapTriggers() public {
        // No deadline before soft cap
        assertEq(presale.softCapReachedAt(), 0);
        assertEq(presale.hardCapDeadline(), 0);

        // Fill to soft cap with multiple users
        for (uint i = 0; i < 5; i++) {
            address u = makeAddr(string(abi.encodePacked("filler", i)));
            vm.deal(u, 2 ether);
            vm.prank(u);
            presale.contribute{value: 1 ether}();
        }

        assertEq(presale.totalRaised(), 5 ether);
        assertTrue(presale.softCapReachedAt() > 0);
        assertEq(presale.hardCapDeadline(), block.timestamp + 5 days);
        assertTrue(presale.isActive()); // still active for hard cap phase
    }

    function test_hardCapCloses() public {
        // Fill to hard cap
        for (uint i = 0; i < 12; i++) {
            address u = makeAddr(string(abi.encodePacked("whale", i)));
            vm.deal(u, 2 ether);
            vm.prank(u);
            presale.contribute{value: 1 ether}();
        }
        // 12 ETH in, add 0.5 more
        address last = makeAddr("last");
        vm.deal(last, 1 ether);
        vm.prank(last);
        presale.contribute{value: 0.5 ether}();

        assertEq(presale.totalRaised(), 12.5 ether);
        assertTrue(presale.presaleClosed());
        assertFalse(presale.isActive());
    }

    function test_timerExpiry() public {
        // Hit soft cap
        for (uint i = 0; i < 5; i++) {
            address u = makeAddr(string(abi.encodePacked("timer", i)));
            vm.deal(u, 2 ether);
            vm.prank(u);
            presale.contribute{value: 1 ether}();
        }

        // Still active
        assertTrue(presale.isActive());

        // Warp past 5 days
        vm.warp(block.timestamp + 5 days + 1);

        // Now expired
        assertFalse(presale.isActive());

        // Anyone can close
        vm.prank(user1);
        presale.closePresale();
        assertTrue(presale.presaleClosed());
    }

    function test_noTimerBeforeSoftCap() public {
        vm.prank(user1);
        presale.contribute{value: 0.1 ether}();

        // Warp 100 days — still active because soft cap not hit
        vm.warp(block.timestamp + 100 days);
        assertTrue(presale.isActive());
    }

    function test_vaultReceivesFunds() public {
        vm.prank(user1);
        presale.contribute{value: 0.5 ether}();
        vm.prank(og1);
        presale.contribute{value: 0.3 ether}();

        // Contract holds nothing
        assertEq(address(presale).balance, 0);
        // Vault has everything
        assertEq(vault.balance, 0.8 ether);
    }

    function test_getAllContributions() public {
        vm.prank(og1);
        presale.contribute{value: 0.5 ether}();
        vm.prank(user1);
        presale.contribute{value: 0.3 ether}();

        (address[] memory wallets, uint256[] memory amounts, uint256[] memory weights, bool[] memory isOGList) = presale.getAllContributions();
        
        assertEq(wallets.length, 2);
        assertEq(amounts[0], 0.5 ether);
        assertEq(weights[0], 0.55 ether); // OG bonus
        assertTrue(isOGList[0]);
        assertEq(amounts[1], 0.3 ether);
        assertEq(weights[1], 0.3 ether); // no bonus
        assertFalse(isOGList[1]);
    }

    function test_cannotContributeAfterClose() public {
        vm.prank(owner);
        presale.closePresale();

        vm.prank(user1);
        vm.expectRevert(ArcaPresaleV2.PresaleNotActive.selector);
        presale.contribute{value: 0.1 ether}();
    }
}
