// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "forge-std/console.sol";
interface ITreasury {
    function getOriginalSender() external view returns (address);
    function initializeCentralWallet(address centralWallet) external;
    function grantAccess(address user) external;
    function revokeAccess(address user) external;
    function hasAccess(address user) external view returns (bool);
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function pause() external;
    function unpause() external;
    function upgradeCentralWallet(address newImplementation) external;
    function owner() external view returns (address);
    function centralWallet() external view returns (address);
    function initialize(address owner) external;
    function paused() external view returns (bool);
}
contract CentralWallet is
    Initializable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    // State variables
    mapping(address => uint256) private balances;
    mapping(address => bool) private authorized;
    uint256 private totalDeposits;

    event Deposit(address indexed depositor, uint256 amount);
    event Withdrawal(address indexed withdrawer, uint256 amount);
    event Initialized(address indexed owner);
    event AuthorizedUser(address indexed user);
    event RevokedUser(address indexed user);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init(_owner);
        __Pausable_init();
        __UUPSUpgradeable_init();

        authorized[_owner] = true;

        emit Initialized(_owner);
    }

    function _getOriginalSender() internal view returns (address) {
        return ITreasury(owner()).getOriginalSender();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal view override onlyOwner {
        require(newImplementation != address(0), "Invalid implementation");
    }

    function deposit() public payable nonReentrant whenNotPaused {
        require(msg.value > 0, "Cannot deposit 0 ether");
        address sender = _getOriginalSender();

        uint256 newBalance = balances[msg.sender] + msg.value;
        require(newBalance >= balances[msg.sender], "Overflow check");

        balances[sender] = newBalance;
        totalDeposits += msg.value;

        emit Deposit(sender, msg.value);
    }

    function withdraw(
        uint256 amount
    ) public nonReentrant whenNotPaused onlyOwner {
        address sender = _getOriginalSender();
        //check if the withdraw was not called from the treasury contract
        require(amount > 0, "Cannot withdraw 0 ether");
        require(
            address(this).balance >= amount,
            "Contract has insufficient funds"
        );

        totalDeposits -= amount;

        (bool success, ) = payable(sender).call{value: amount}("");
        require(success, "Withdrawal failed");

        emit Withdrawal(sender, amount);
    }

    function getContractBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getBalance(address account) external view returns (uint256) {
        return balances[account];
    }

    function getTotalDeposits() public view returns (uint256) {
        return totalDeposits;
    }
    // Emergency functions

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Fallback and receive functions to accept Ether
    receive() external payable {
        deposit();
    }

    fallback() external payable {
        deposit();
    }
}
