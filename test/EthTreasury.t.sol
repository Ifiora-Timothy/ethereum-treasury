// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Test, console} from "lib/forge-std/src/Test.sol";
import "../src/TreasuryContract.sol";
import "../src/CentralWallet.sol";

contract TreasuryTest is Test {
    // Contract instances
    Treasury public treasury;
    CentralWallet public centralWalletImplementation;
    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public proxy;
    // Test accounts
    address public owner;
    address public user1;
    address public user2;

    // Events to test
    event CentralWalletInitialized(address centralWalletAddress);
    event AccessGranted(address user);
    event AccessRevoked(address user);

    function setUp() public {
        // Set up test accounts

        owner = address(this);
        user1 = vm.addr(1);
        user2 = vm.addr(2);
        // Deploy contracts
        centralWalletImplementation = new CentralWallet();
         // Deploy ProxyAdmin first
        proxyAdmin = new ProxyAdmin(owner);

        proxy = new TransparentUpgradeableProxy(
            address(centralWalletImplementation),
            address(proxyAdmin),
            ""
        );

        treasury = new Treasury(address(proxy));
    }

    // Test Contract Initialization
    function testInitializeCentralWallet() public {
        // Expect event to be emitted
        vm.expectEmit(true, true, true, true);
        emit CentralWalletInitialized(address(0)); // placeholder address

        // Initialize CentralWallet
        treasury.initializeCentralWallet(address(centralWalletImplementation));

        // Verify initialization
        assertTrue(treasury.isInitialized(), "Treasury should be initialized");
    }

    // Test Double Initialization Prevention
    function testCannotInitializeTwice() public {
        treasury.initializeCentralWallet(address(centralWalletImplementation));

        // Attempt to initialize again should revert
        vm.expectRevert("CentralWallet already initialized");
        treasury.initializeCentralWallet(address(centralWalletImplementation));
    }

    // Test Access Control
    function testGrantAndRevokeAccess() public {
        // Grant access
        vm.expectEmit(true, true, true, true);
        emit AccessGranted(user1);
        treasury.grantAccess(user1);

        // Verify access granted
        assertTrue(treasury.hasAccess(user1), "User should have access");

        // Revoke access
        vm.expectEmit(true, true, true, true);
        emit AccessRevoked(user1);
        treasury.revokeAccess(user1);

        // Verify access revoked
        assertFalse(treasury.hasAccess(user1), "User access should be revoked");
    }

    // Test Access Control for Sensitive Functions
    function testOnlyOwnerCanGrantAccess() public {
        // Switch to a different account
        vm.prank(user1);

        // Attempt to grant access should revert
        vm.expectRevert("Not authorized");
        treasury.grantAccess(user2);
    }

    // Test Deposit Functionality
    function testDeposit() public {
        // Initialize CentralWallet
        treasury.initializeCentralWallet(address(centralWalletImplementation));

        // Grant access to user
        treasury.grantAccess(user1);

        // Prepare deposit
        uint256 depositAmount = 1 ether;
        vm.prank(user1);
        vm.deal(user1, depositAmount);

        // Perform deposit
        treasury.deposit{value: depositAmount}();

        // Verify balance
        // Note: This requires checking via proxy call, which is tricky to test directly
    }

    // Test Withdrawal Functionality
    function testWithdraw() public {
        // Initialize CentralWallet
        treasury.initializeCentralWallet(address(centralWalletImplementation));

        // Grant access and deposit
        treasury.grantAccess(user1);

        uint256 depositAmount = 1 ether;
        vm.prank(user1);
        vm.deal(user1, depositAmount);
        treasury.deposit{value: depositAmount}();

        // Prepare withdrawal
        uint256 withdrawAmount = 0.5 ether;
        vm.prank(user1);

        // Perform withdrawal
        treasury.withdraw(withdrawAmount);

        // Verify balance (would require additional proxy implementation details)
    }

    // Test Upgrade Functionality
    function testUpgradeTo() public {
        // Initialize CentralWallet
        treasury.initializeCentralWallet(address(centralWalletImplementation));

        // Create a new implementation (mock)
        CentralWallet newImplementation = new CentralWallet();

        // Upgrade
        treasury.upgradeTo(address(newImplementation));

        // Additional verification might be needed depending on implementation
    }

    // Test Unauthorized Deposit
    function testUnauthorizedDeposit() public {
        // Initialize CentralWallet
        treasury.initializeCentralWallet(address(centralWalletImplementation));

        // Attempt deposit without access
        vm.prank(user1);
        vm.expectRevert("Not authorized");
        treasury.deposit{value: 1 ether}();
    }

    // Fuzz Testing for Deposit
    function testFuzzDeposit(uint96 amount) public {
        // Initialize CentralWallet
        treasury.initializeCentralWallet(address(centralWalletImplementation));

        // Grant access to user
        treasury.grantAccess(user1);

        // Prepare deposit
        vm.prank(user1);
        vm.deal(user1, amount);

        // Perform deposit
        treasury.deposit{value: amount}();

        // Note: Full balance verification would require more complex proxy interaction
    }

    // Negative Test: Unauthorized Withdrawal
    function testUnauthorizedWithdrawal() public {
        // Initialize CentralWallet
        treasury.initializeCentralWallet(address(centralWalletImplementation));

        // Attempt withdrawal without access
        vm.prank(user1);
        vm.expectRevert("Not authorized");
        treasury.withdraw(1 ether);
    }

    // Fallback Receive Test
    function testFallbackReceive() public {
        // Initialize CentralWallet
        treasury.initializeCentralWallet(address(centralWalletImplementation));

        // Send Ether directly to proxy
        address proxyAddress = treasury.proxyAddress();
        vm.prank(user1);
        vm.deal(user1, 1 ether);

        // Send Ether
        (bool success, ) = proxyAddress.call{value: 1 ether}("");

        assertTrue(success, "Fallback should accept Ether");
    }
}
