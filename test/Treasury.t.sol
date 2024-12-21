// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/OptimisedTreasury.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IPausableErrors {
    error EnforcedPause();
    error ExpectedPause();
}

interface InitializionErrors {
    error InvalidInitialization();
}
interface IOptimizedTreasury {
    function owner() external view returns (address);
    function hasAccess(address user) external view returns (bool);
    function initialize(address owner) external;
    function grantAccess(address user) external;
    function revokeAccess(address user) external;
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function pause() external;
    function unpause() external;
    function getBalance(address account) external view returns (uint256);
    function getContractBalance() external view returns (uint256);
    function getTotalDeposits() external view returns (uint256);
    function paused() external view returns (bool);
    function upgradeToAndCall(
        address newImplementation,
        bytes memory data
    ) external payable;
    function getAccessList() external view returns (address[] memory);
}

contract OptimizedTreasuryTest is Test {
    IOptimizedTreasury public treasuryImplementation;
    IOptimizedTreasury public treasury;

    address public owner;
    address public user1;
    address public user2;
    address public attacker;

    uint256 constant INITIAL_BALANCE = 100 ether;
    uint256 constant MAX_WITHDRAWAL = 100 ether;

    event Deposit(address indexed depositor, uint256 amount);
    event Withdrawal(address indexed withdrawer, uint256 amount);
    event AccessGranted(address indexed user);
    event AccessRevoked(address indexed user);

    function setUp() public {
        // Set up test accounts
        owner = address(this);
        user1 = vm.addr(1);
        user2 = vm.addr(2);
        attacker = vm.addr(3);

        // Deploy implementation contract
        treasuryImplementation = IOptimizedTreasury(
            address(new OptimizedTreasury())
        );

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            OptimizedTreasury.initialize.selector,
            owner
        );

        ERC1967Proxy treasuryProxy = new ERC1967Proxy(
            address(treasuryImplementation),
            initData
        );

        treasury = IOptimizedTreasury(payable(address(treasuryProxy)));
    }

    // Initialization Tests
    function testCorrectInitialization() public view {
        assertEq(treasury.owner(), owner, "Owner not set correctly");
        assertTrue(
            treasury.hasAccess(owner),
            "Owner should have initial access"
        );
    }

    function testCannotInitializeTwice() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                InitializionErrors.InvalidInitialization.selector
            )
        );
        treasury.initialize(owner);
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
    function testDeposit() public {
        uint256 depositAmount = 1 ether;
        vm.deal(user1, depositAmount);

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit Deposit(user1, depositAmount);
        treasury.deposit{value: depositAmount}();

        assertEq(treasury.getBalance(user1), depositAmount);
        assertEq(treasury.getContractBalance(), depositAmount);
        assertEq(treasury.getTotalDeposits(), depositAmount);
    }

    function testZeroValueDeposit() public {
        vm.prank(user1);
        vm.expectRevert("Cannot deposit 0 ether");
        treasury.deposit{value: 0}();
    }

    // Withdrawal Tests
    function testAuthorizedWithdrawal() public {
        uint256 depositAmount = 5 ether;
        uint256 withdrawAmount = 2 ether;

        treasury.grantAccess(user1);
        vm.deal(user1, depositAmount);

        // Deposit
        vm.prank(user1);
        treasury.deposit{value: depositAmount}();

        // Withdraw
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit Withdrawal(user1, withdrawAmount);
        treasury.withdraw(withdrawAmount);

        assertEq(user1.balance, withdrawAmount);
        assertEq(treasury.getBalance(user1), depositAmount - withdrawAmount);
        assertEq(treasury.getContractBalance(), depositAmount - withdrawAmount);
    }

    function testUnauthorizedWithdrawal() public {
        uint256 depositAmount = 5 ether;

        vm.deal(attacker, depositAmount);

        // Deposit
        vm.prank(attacker);
        treasury.deposit{value: depositAmount}();

        // Attempt withdrawal
        vm.prank(attacker);
        vm.expectRevert("Not authorized");
        treasury.withdraw(1 ether);
    }

    function testCannotWithdrawMoreThanBalance() public {
        uint256 depositAmount = 5 ether;
        treasury.grantAccess(user1);

        vm.deal(user1, depositAmount);
        vm.prank(user1);
        treasury.deposit{value: depositAmount}();

        vm.prank(user1);
        vm.expectRevert("Insufficient contract balance");
        treasury.withdraw(6 ether);
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
        OptimizedTreasury newImplementation = new OptimizedTreasury();

        // Initial state
        uint256 initialBalance = 1 ether;
        treasury.grantAccess(user1);
        vm.deal(user1, initialBalance);
        vm.prank(user1);
        treasury.deposit{value: initialBalance}();

        // Upgrade
        vm.prank(owner); // Only owner can upgrade
        treasury.upgradeToAndCall(
            address(newImplementation),
            "" // No initialization data needed
        );

        // Verify state is preserved
        assertEq(treasury.getBalance(user1), initialBalance);
        assertEq(treasury.getContractBalance(), initialBalance);
        assertTrue(treasury.hasAccess(user1));
    }

    // Fallback and Receive Tests
    function testFallbackAndReceive() public {
        vm.deal(user1, 2 ether);

        // Test receive function
        vm.prank(user1);
        (bool success, ) = address(treasury).call{value: 1 ether}("");
        assertTrue(success, "Receive function failed");

        // Test fallback function
        vm.prank(user1);
        (success, ) = address(treasury).call{value: 1 ether}(hex"12345678");
        assertTrue(success, "Fallback function failed");

        assertEq(treasury.getBalance(user1), 2 ether);
    }

    // Fuzz Tests
    function testFuzzDeposit(uint96 amount) public {
        vm.assume(amount > 0 && amount <= MAX_WITHDRAWAL);
        vm.deal(user1, amount);

        vm.prank(user1);
        treasury.deposit{value: amount}();

        assertEq(treasury.getBalance(user1), amount);
        assertEq(treasury.getContractBalance(), amount);
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
        assertEq(treasury.getBalance(user1), depositAmount - withdrawAmount);
    }
}
