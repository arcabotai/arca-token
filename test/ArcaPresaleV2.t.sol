// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/ArcaPresaleV2.sol";

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
}

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
        presale = new ArcaPresaleV2(block.timestamp, vault, ogWallets);
    }

    // ─── Basic Tests ─────────────────────────────────────────────────

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
        assertEq(presale.remainingCapacity(), 12.5 ether);
    }

    function test_contribute() public {
        vm.prank(user1);
        presale.contribute{value: 0.1 ether}();

        assertEq(presale.contributions(user1), 0.1 ether);
        assertEq(presale.totalRaised(), 0.1 ether);
        assertEq(vault.balance, 0.1 ether);
        assertEq(presale.getContributorCount(), 1);
        assertEq(presale.remainingCapacity(), 12.4 ether);
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
        assertEq(presale.getAllocationWeight(og1), 1.1 ether);
        
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
        assertEq(presale.softCapReachedAt(), 0);
        assertEq(presale.hardCapDeadline(), 0);

        for (uint i = 0; i < 5; i++) {
            address u = makeAddr(string(abi.encodePacked("filler", i)));
            vm.deal(u, 2 ether);
            vm.prank(u);
            presale.contribute{value: 1 ether}();
        }

        assertEq(presale.totalRaised(), 5 ether);
        assertTrue(presale.softCapReachedAt() > 0);
        assertEq(presale.hardCapDeadline(), block.timestamp + 5 days);
        assertTrue(presale.isActive());
    }

    function test_hardCapCloses() public {
        for (uint i = 0; i < 12; i++) {
            address u = makeAddr(string(abi.encodePacked("whale", i)));
            vm.deal(u, 2 ether);
            vm.prank(u);
            presale.contribute{value: 1 ether}();
        }
        address last = makeAddr("last");
        vm.deal(last, 1 ether);
        vm.prank(last);
        presale.contribute{value: 0.5 ether}();

        assertEq(presale.totalRaised(), 12.5 ether);
        assertTrue(presale.presaleClosed());
        assertFalse(presale.isActive());
    }

    function test_timerExpiry() public {
        for (uint i = 0; i < 5; i++) {
            address u = makeAddr(string(abi.encodePacked("timer", i)));
            vm.deal(u, 2 ether);
            vm.prank(u);
            presale.contribute{value: 1 ether}();
        }
        assertTrue(presale.isActive());
        vm.warp(block.timestamp + 5 days + 1);
        assertFalse(presale.isActive());
        vm.prank(user1);
        presale.closePresale();
        assertTrue(presale.presaleClosed());
    }

    function test_noTimerBeforeSoftCap() public {
        vm.prank(user1);
        presale.contribute{value: 0.1 ether}();
        vm.warp(block.timestamp + 100 days);
        assertTrue(presale.isActive());
    }

    function test_vaultReceivesFunds() public {
        vm.prank(user1);
        presale.contribute{value: 0.5 ether}();
        vm.prank(og1);
        presale.contribute{value: 0.3 ether}();
        assertEq(address(presale).balance, 0);
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
        assertEq(weights[0], 0.55 ether);
        assertTrue(isOGList[0]);
        assertEq(amounts[1], 0.3 ether);
        assertEq(weights[1], 0.3 ether);
        assertFalse(isOGList[1]);
    }

    function test_cannotContributeAfterClose() public {
        vm.prank(owner);
        presale.closePresale();

        vm.prank(user1);
        vm.expectRevert(ArcaPresaleV2.PresaleNotActive.selector);
        presale.contribute{value: 0.1 ether}();
    }

    // ─── Partial Fill Tests ──────────────────────────────────────────

    function test_partialFillAtHardCap() public {
        // Fill to 12 ETH
        for (uint i = 0; i < 12; i++) {
            address u = makeAddr(string(abi.encodePacked("fill", i)));
            vm.deal(u, 2 ether);
            vm.prank(u);
            presale.contribute{value: 1 ether}();
        }
        assertEq(presale.totalRaised(), 12 ether);
        assertEq(presale.remainingCapacity(), 0.5 ether);

        // User sends 1 ETH but only 0.5 fits — should partial fill
        address partialUser = makeAddr("partial");
        vm.deal(partialUser, 2 ether);
        uint256 balBefore = partialUser.balance;
        
        vm.prank(partialUser);
        presale.contribute{value: 1 ether}();

        // Only 0.5 accepted, 0.5 returned
        assertEq(presale.contributions(partialUser), 0.5 ether);
        assertEq(presale.totalRaised(), 12.5 ether);
        assertEq(partialUser.balance, balBefore - 0.5 ether); // got 0.5 back
        assertTrue(presale.presaleClosed());
        assertEq(vault.balance, 12.5 ether);
    }

    function test_partialFillSmallRemaining() public {
        // Fill to 12.49 ETH
        for (uint i = 0; i < 12; i++) {
            address u = makeAddr(string(abi.encodePacked("small", i)));
            vm.deal(u, 2 ether);
            vm.prank(u);
            presale.contribute{value: 1 ether}();
        }
        address a = makeAddr("smallA");
        vm.deal(a, 1 ether);
        vm.prank(a);
        presale.contribute{value: 0.49 ether}();

        // Only 0.01 ETH remaining — user sends 0.5 ETH
        address b = makeAddr("smallB");
        vm.deal(b, 1 ether);
        uint256 balBefore = b.balance;

        vm.prank(b);
        presale.contribute{value: 0.5 ether}();

        assertEq(presale.contributions(b), 0.01 ether);
        assertEq(b.balance, balBefore - 0.01 ether); // got 0.49 back
        assertEq(presale.totalRaised(), 12.5 ether);
        assertTrue(presale.presaleClosed());
    }

    // ─── ERC-20 Rescue Tests ─────────────────────────────────────────

    function test_rescueERC20() public {
        MockERC20 token = new MockERC20();
        token.mint(address(presale), 1000); // simulate accidental token transfer
        assertEq(token.balanceOf(address(presale)), 1000);

        // Owner rescues tokens
        vm.prank(owner);
        presale.rescueTokens(address(token), user1, 1000);

        assertEq(token.balanceOf(address(presale)), 0);
        assertEq(token.balanceOf(user1), 1000);
    }

    function test_rescueOnlyOwner() public {
        MockERC20 token = new MockERC20();
        token.mint(address(presale), 1000);

        vm.prank(user1);
        vm.expectRevert(ArcaPresaleV2.OnlyOwner.selector);
        presale.rescueTokens(address(token), user1, 1000);
    }

    // ─── Edge Case Tests (security audit) ────────────────────────────

    function test_contractAlwaysZeroBalance() public {
        vm.prank(user1);
        presale.contribute{value: 0.5 ether}();
        vm.prank(og1);
        presale.contribute{value: 1 ether}();
        assertEq(address(presale).balance, 0);
    }

    function test_cumulativeMaxEnforced() public {
        vm.startPrank(user1);
        presale.contribute{value: 0.3 ether}();
        presale.contribute{value: 0.3 ether}();
        presale.contribute{value: 0.3 ether}();
        assertEq(presale.contributions(user1), 0.9 ether);
        vm.expectRevert(ArcaPresaleV2.AboveMaximum.selector);
        presale.contribute{value: 0.2 ether}();
        vm.stopPrank();
    }

    function test_ogZeroContributionZeroWeight() public {
        assertEq(presale.getAllocationWeight(og1), 0);
        assertTrue(presale.isOG(og1));
    }

    function test_ownerEarlyClose() public {
        vm.prank(user1);
        presale.contribute{value: 0.1 ether}();
        vm.prank(owner);
        presale.closePresale();
        assertTrue(presale.presaleClosed());
        assertEq(vault.balance, 0.1 ether);
    }

    function test_nonOwnerCannotClose() public {
        vm.prank(user1);
        vm.expectRevert(ArcaPresaleV2.OnlyOwner.selector);
        presale.closePresale();
    }

    function test_doubleClose() public {
        vm.prank(owner);
        presale.closePresale();
        vm.prank(owner);
        vm.expectRevert(ArcaPresaleV2.AlreadyClosed.selector);
        presale.closePresale();
    }

    function test_noDuplicateContributors() public {
        vm.startPrank(user1);
        presale.contribute{value: 0.1 ether}();
        presale.contribute{value: 0.1 ether}();
        presale.contribute{value: 0.1 ether}();
        vm.stopPrank();
        assertEq(presale.getContributorCount(), 1);
    }

    function test_remainingCapacityUpdates() public {
        assertEq(presale.remainingCapacity(), 12.5 ether);
        vm.prank(user1);
        presale.contribute{value: 1 ether}();
        assertEq(presale.remainingCapacity(), 11.5 ether);
    }

    // ─── StartTime Tests ─────────────────────────────────────────────

    function test_cannotContributeBeforeStart() public {
        // Deploy a new presale with future start time
        address[] memory ogWallets = new address[](0);
        vm.prank(owner);
        ArcaPresaleV2 futurePresale = new ArcaPresaleV2(block.timestamp + 1 hours, vault, ogWallets);

        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert(ArcaPresaleV2.NotStarted.selector);
        futurePresale.contribute{value: 0.1 ether}();
    }

    function test_canContributeAfterStart() public {
        address[] memory ogWallets = new address[](0);
        vm.prank(owner);
        ArcaPresaleV2 futurePresale = new ArcaPresaleV2(block.timestamp + 1 hours, vault, ogWallets);

        // Warp past start time
        vm.warp(block.timestamp + 1 hours + 1);

        vm.deal(user1, 1 ether);
        vm.prank(user1);
        futurePresale.contribute{value: 0.1 ether}();
        assertEq(futurePresale.totalRaised(), 0.1 ether);
    }

    function test_isStartedView() public {
        address[] memory ogWallets = new address[](0);
        vm.prank(owner);
        ArcaPresaleV2 futurePresale = new ArcaPresaleV2(block.timestamp + 1 hours, vault, ogWallets);

        assertFalse(futurePresale.isStarted());
        assertFalse(futurePresale.isActive());

        vm.warp(block.timestamp + 1 hours + 1);
        assertTrue(futurePresale.isStarted());
        assertTrue(futurePresale.isActive());
    }
}
