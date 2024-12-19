// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "../src/TreasuryContract.sol";
import "../src/CentralWallet.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// Import custom errors from OpenZeppelin contracts
interface IPausableErrors {
    error ExpectedPause();
    error EnforcedPause();
}

contract TreasuryTest is Test {
    // Contract instances
    Treasury public treasury;
    Treasury public treasuryImplementation;
    CentralWallet public centralWalletImplementation;

    // Test accounts
    address public owner;
    address public user1;
    address public user2;
    address public attacker;

    // Constants for testing
    uint256 constant INITIAL_BALANCE = 100 ether;
    uint256 constant MAX_WITHDRAWAL = 100 ether;

    // Events
    event CentralWalletInitialized(address centralWalletAddress);
    event AccessGranted(address indexed user);
    event AccessRevoked(address indexed user);
    event Deposit(address indexed depositor, uint256 amount);
    event Withdrawal(address indexed withdrawer, uint256 amount);

    function setUp() public {
        // Set up test accounts
        owner = address(this);
        user1 = vm.addr(1);
        user2 = vm.addr(2);
        attacker = vm.addr(3);

        // Deploy implementation contracts
        treasuryImplementation = new Treasury();
        centralWalletImplementation = new CentralWallet();

        // Deploy proxy for Treasury
        bytes memory initData = abi.encodeWithSelector(
            Treasury.initialize.selector,
            owner
        );

        ERC1967Proxy treasuryProxy = new ERC1967Proxy(
            address(treasuryImplementation),
            initData
        );

        treasury = Treasury(payable(address(treasuryProxy)));

        // Initialize CentralWallet through Treasury
        treasury.initializeCentralWallet(address(centralWalletImplementation));
    }

    // Initialization Tests
    function testCorrectInitialization() public view {
        assertTrue(treasury.owner() == owner, "Owner not set correctly");
        assertTrue(
            treasury.centralWallet() != address(0),
            "Central wallet not initialized"
        );
    }

    function testCannotInitializeTwice() public {
        vm.expectRevert("Already initialized");
        treasury.initializeCentralWallet(address(centralWalletImplementation));
    }

    // Access Control Tests
    function testAccessControl() public {
        // Grant access
        vm.expectEmit(true, true, true, true);
        emit AccessGranted(user1);
        treasury.grantAccess(user1);
        assertTrue(treasury.hasAccess(user1), "Access not granted");

        // Revoke access
        vm.expectEmit(true, true, true, true);
        emit AccessRevoked(user1);
        treasury.revokeAccess(user1);
        assertFalse(treasury.hasAccess(user1), "Access not revoked");
    }

    function testOnlyOwnerCanGrantAccess() public {
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
                attacker
            )
        );
        treasury.grantAccess(user2);
    }

    function testCannotGrantAccessToZeroAddress() public {
        vm.expectRevert("Invalid address");
        treasury.grantAccess(address(0));
    }

    // Deposit Tests
    function testAuthorizedDeposit() public {
        uint256 depositAmount = 1 ether;
        treasury.grantAccess(user1);

        vm.deal(user1, depositAmount);
        vm.prank(user1);

        vm.expectEmit(true, true, true, true);
        emit Deposit(user1, depositAmount);
        treasury.deposit{value: depositAmount}();

        assertEq(address(treasury.centralWallet()).balance, depositAmount);
    }
    function testUnauthorizedDeposit() public {
        vm.deal(attacker, 1 ether);
        vm.prank(attacker);
        vm.expectRevert("Not authorized");
        treasury.deposit{value: 1 ether}();
    }

    function testZeroValueDeposit() public {
        treasury.grantAccess(user1);
        vm.prank(user1);
        vm.expectRevert("Cannot forward zero value");
        treasury.deposit{value: 0}();
    }

    function testCentralWalletBalanceAfterDeposit() public {
        uint256 depositAmount = 1 ether;
        treasury.grantAccess(user1);

        vm.deal(user1, depositAmount);
        vm.prank(user1);

        treasury.deposit{value: depositAmount}();

        // Verify the balance of the central wallet
        (bool success, bytes memory returnData) = treasury.centralWallet().call{
            value: 0
        }(abi.encodeWithSelector(CentralWallet.getBalance.selector, user1));
        require(success, "Failed to get balance");

        uint256 balance = abi.decode(returnData, (uint256));
        assertEq(balance, depositAmount, "Central wallet balance mismatch");
    }

    // Withdrawal Tests
    function testAuthorizedWithdrawal2() public {
        uint256 depositAmount = 5 ether;
        uint256 withdrawAmount = 2 ether;

        treasury.grantAccess(user1);
        treasury.grantAccess(user2);
        vm.deal(user1, depositAmount);
        vm.deal(user2, depositAmount);

        // Deposit first
        vm.prank(user1);
        treasury.deposit{value: depositAmount}();
        // Deposit second
        vm.prank(user2);
        treasury.deposit{value: depositAmount}();

        // Check balances
        (bool success1, bytes memory returnData1) = treasury
            .centralWallet()
            .call{value: 0}(
            abi.encodeWithSelector(CentralWallet.getBalance.selector, user1)
        );
        require(success1, "Failed to get balance");
        uint256 balance1 = abi.decode(returnData1, (uint256));

        (bool success2, bytes memory returnData2) = treasury
            .centralWallet()
            .call{value: 0}(
            abi.encodeWithSelector(CentralWallet.getBalance.selector, user2)
        );
        require(success2, "Failed to get balance");
        uint256 balance2 = abi.decode(returnData2, (uint256));

        console.log(
            "Central wallet balance:",
            address(treasury.centralWallet()).balance
        );
        console.log("User1 balance from getBalance:", balance1);
        console.log("User2 balance from getBalance:", balance2);

        // Then withdraw
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit Withdrawal(user1, withdrawAmount);
        treasury.withdraw(withdrawAmount);

        assertEq(user1.balance, withdrawAmount);
    }
    function testCannotWithdrawMoreThanBalance() public {
        treasury.grantAccess(user1);
        vm.deal(user1, 1 ether);

        vm.prank(user1);
        treasury.deposit{value: 1 ether}();

        vm.prank(user1);
        vm.expectRevert("Insufficient balance");
        treasury.withdraw(2 ether);
    }
    function testCannotExceedMaxWithdrawal() public {
        treasury.grantAccess(user1);
        vm.deal(user1, MAX_WITHDRAWAL + 1 ether);

        vm.prank(user1);
        treasury.deposit{value: MAX_WITHDRAWAL + 1 ether}();

        vm.prank(user1);
        vm.expectRevert("Amount exceeds maximum withdrawal limit");
        treasury.withdraw(MAX_WITHDRAWAL + 1);
    }
    // Pause Tests
    function testPauseAndUnpause() public {
        // Pause
        treasury.pause();
        assertTrue(treasury.paused(), "Contract should be paused");

        // Try deposit while paused
        treasury.grantAccess(user1);
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(IPausableErrors.EnforcedPause.selector)
        );
        treasury.deposit{value: 1 ether}();

        // Unpause
        treasury.unpause();
        assertFalse(treasury.paused(), "Contract should be unpaused");

        // Deposit should work now
        vm.prank(user1);
        treasury.deposit{value: 1 ether}();
    }

    // Upgrade Tests
    function testUpgrade() public {
        // Deploy new implementation
        CentralWallet newImplementation = new CentralWallet();

        // Check initial state
        uint256 initialBalance = 1 ether;
        treasury.grantAccess(user1);
        vm.deal(user1, initialBalance);
        vm.prank(user1);
        treasury.deposit{value: initialBalance}();

        // Pause before upgrade
        treasury.pause();

        // Upgrade
        treasury.upgradeCentralWallet(address(newImplementation));

        // Verify upgrade
        assertTrue(treasury.centralWallet() != address(0));

        // Test functionality after upgrade
        treasury.unpause();
        vm.deal(user1, initialBalance);
        vm.prank(user1);
        treasury.deposit{value: initialBalance}();

        // Verify balance is preserved
        assertEq(address(treasury.centralWallet()).balance, initialBalance * 2);
    }

    function testCannotUpgradeWhenNotPaused() public {
        CentralWallet newImplementation = new CentralWallet();
        vm.expectRevert(
            abi.encodeWithSelector(IPausableErrors.ExpectedPause.selector)
        );
        treasury.upgradeCentralWallet(address(newImplementation));
    }

    function testCannotUpgradeToZeroAddress() public {
        treasury.pause();
        vm.expectRevert("Invalid implementation");
        treasury.upgradeCentralWallet(address(0));
    }

    // Fallback and Receive Tests
    function testFallbackAndReceive() public {
        treasury.grantAccess(user1);
        vm.deal(user1, 1 ether);

        // Test receive function
        vm.prank(user1);
        (bool success, ) = address(treasury).call{value: 1 ether}("");
        assertTrue(success, "Receive function failed");

        // Test fallback function
        vm.prank(user1);
        vm.deal(user1, 1 ether);
        (success, ) = address(treasury).call{value: 1 ether}(hex"12345678");
        assertTrue(success, "Fallback function failed");
    }

    // Fuzz Tests
    function testFuzzDeposit(uint96 amount) public {
        vm.assume(amount > 0 && amount <= MAX_WITHDRAWAL);

        treasury.grantAccess(user1);
        vm.deal(user1, amount);

        vm.prank(user1);
        treasury.deposit{value: amount}();

        assertEq(address(treasury.centralWallet()).balance, amount);
    }

    function testFuzzWithdrawal(
        uint96 depositAmount,
        uint96 withdrawAmount
    ) public {
        vm.assume(depositAmount > 0 && depositAmount <= MAX_WITHDRAWAL);
        vm.assume(withdrawAmount > 0 && withdrawAmount <= depositAmount);

        treasury.grantAccess(user1);
        vm.deal(user1, depositAmount);

        vm.prank(user1);
        treasury.deposit{value: depositAmount}();

        vm.prank(user1);
        treasury.withdraw(withdrawAmount);

        assertEq(user1.balance, withdrawAmount);
    }
}
