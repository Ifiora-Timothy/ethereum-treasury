// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

interface ITreasury {
    function getOriginalSender() external view returns (address);
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
    uint256 private totalDeposits;

    event Deposit(address indexed depositor, uint256 amount);
    event Withdrawal(address indexed withdrawer, uint256 amount);
    event Initialized(address indexed owner);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init(_owner);
        __Pausable_init();
        __UUPSUpgradeable_init();

        emit Initialized(_owner);
    }

    function _getOriginalSender() internal view returns (address) {
        return ITreasury(owner()).getOriginalSender();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal view override onlyOwner {
        // Add custom upgrade logic if needed
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

    function withdraw(uint256 amount) public nonReentrant whenNotPaused {
        address sender = _getOriginalSender();

        require(amount > 0, "Cannot withdraw 0 ether");
        require(balances[sender] >= amount, "Insufficient balance");
        require(
            address(this).balance >= amount,
            "Contract has insufficient funds"
        );

        balances[sender] -= amount;
        totalDeposits -= amount;

        // Use low level call with CEI pattern
        (bool success, ) = payable(sender).call{value: amount}("");
        require(success, "Withdrawal failed");

        emit Withdrawal(sender, amount);
    }

    function getContractBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getBalance(address account) public view returns (uint256) {
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
