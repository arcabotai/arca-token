// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/ArcaPresaleV2.sol";

/// @notice Fork test — runs against real Base mainnet state
/// Tests the full presale flow with the actual Gnosis Safe vault
contract ArcaPresaleV2ForkTest is Test {
    ArcaPresaleV2 presale;
    
    // Real addresses
    address payable constant VAULT = payable(0x9a0756D4e1b2361d25D99701e1B8Ab87eC262692); // vault.arcabot.eth
    address constant ARCA = 0x1be93C700dDC596D701E8F2106B8F9166C625Adb; // arcabot.eth
    address constant FELIPE = 0x281E6843cC18c8d58eE131309F788879F6C18D10; // felirami.eth
    
    // Sample OG addresses (first 3 from whitelist)
    address constant OG1 = 0x03fFeaf9aa455827D76DD439aeAa4496D26cF80C;
    address constant OG2 = 0x0Dd29A896E1f200efDF2f6DF76D27E23df04413d;
    address constant OG3 = 0x193BB437B1494492A068193FEbF4f47263C8eB23;
    
    function setUp() public {
        // Deploy presale with real vault and 3 OG wallets
        address[] memory ogWallets = new address[](3);
        ogWallets[0] = OG1;
        ogWallets[1] = OG2;
        ogWallets[2] = OG3;
        
        // Deploy as Arca (owner)
        vm.prank(ARCA);
        presale = new ArcaPresaleV2(block.timestamp, VAULT, ogWallets);
        
        // Fund test participants
        vm.deal(OG1, 2 ether);
        vm.deal(OG2, 2 ether);
        vm.deal(OG3, 2 ether);
        vm.deal(FELIPE, 2 ether);
        vm.deal(address(0xBEEF), 2 ether);
    }
    
    function test_fork_vaultIsGnosisSafe() public view {
        // Verify the vault is a contract (Gnosis Safe)
        uint256 codeSize;
        address v = address(VAULT);
        assembly { codeSize := extcodesize(v) }
        assertTrue(codeSize > 0, "Vault should be a contract (Gnosis Safe)");
    }
    
    function test_fork_contributeForwardsToSafe() public {
        uint256 vaultBefore = VAULT.balance;
        
        vm.prank(FELIPE);
        presale.contribute{value: 0.5 ether}();
        
        // Vault received the ETH
        assertEq(VAULT.balance, vaultBefore + 0.5 ether);
        // Contract holds nothing
        assertEq(address(presale).balance, 0);
        // Contribution tracked
        assertEq(presale.contributions(FELIPE), 0.5 ether);
    }
    
    function test_fork_ogBonusWorks() public {
        vm.prank(OG1);
        presale.contribute{value: 1 ether}();
        
        // OG gets 10% bonus weight
        assertEq(presale.getAllocationWeight(OG1), 1.1 ether);
        
        // Felipe (non-OG) gets 1:1
        vm.prank(FELIPE);
        presale.contribute{value: 1 ether}();
        assertEq(presale.getAllocationWeight(FELIPE), 1 ether);
    }
    
    function test_fork_partialFillReturnsFunds() public {
        // Fill to 12 ETH
        for (uint i = 0; i < 12; i++) {
            address filler = makeAddr(string(abi.encodePacked("fork_filler", i)));
            vm.deal(filler, 2 ether);
            vm.prank(filler);
            presale.contribute{value: 1 ether}();
        }
        
        // 0.5 ETH remaining — Felipe sends 1 ETH
        uint256 felipeBefore = FELIPE.balance;
        vm.prank(FELIPE);
        presale.contribute{value: 1 ether}();
        
        // Only 0.5 accepted, 0.5 returned
        assertEq(presale.contributions(FELIPE), 0.5 ether);
        assertEq(FELIPE.balance, felipeBefore - 0.5 ether);
        assertEq(presale.totalRaised(), 12.5 ether);
        assertTrue(presale.presaleClosed());
    }
    
    function test_fork_fullPresaleFlow() public {
        // 1. OG contributes
        vm.prank(OG1);
        presale.contribute{value: 0.5 ether}();
        assertTrue(presale.isActive());
        assertEq(presale.softCapReachedAt(), 0); // soft cap not hit yet
        
        // 2. Fill to soft cap
        for (uint i = 0; i < 5; i++) {
            address filler = makeAddr(string(abi.encodePacked("flow_filler", i)));
            vm.deal(filler, 2 ether);
            vm.prank(filler);
            presale.contribute{value: 1 ether}();
        }
        
        // 5.5 ETH raised — soft cap hit!
        assertTrue(presale.softCapReachedAt() > 0);
        assertTrue(presale.isActive()); // still active for hard cap
        assertTrue(presale.timeRemaining() > 0);
        
        // 3. More contributions
        vm.prank(FELIPE);
        presale.contribute{value: 1 ether}();
        
        // 4. Get all contributions for airdrop
        (address[] memory wallets, uint256[] memory amounts, uint256[] memory weights, bool[] memory isOGList) = presale.getAllContributions();
        assertTrue(wallets.length >= 7);
        
        // 5. OG1 should have bonus weight
        bool foundOG = false;
        for (uint i = 0; i < wallets.length; i++) {
            if (wallets[i] == OG1) {
                assertTrue(isOGList[i]);
                assertEq(weights[i], 0.55 ether); // 0.5 + 10% = 0.55
                foundOG = true;
            }
        }
        assertTrue(foundOG);
    }
    
    function test_fork_ownerIsArca() public view {
        assertEq(presale.owner(), ARCA);
    }
}
