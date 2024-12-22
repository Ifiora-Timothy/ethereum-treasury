// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract OptimizedTreasury2 is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable
{
    mapping(address => uint256) private balances;
    mapping(address => bool) public hasAccess;
    address[] public authorizedAddresses;
    uint256 private totalDeposits;
    uint256 private constant MAX_WITHDRAWAL = 100 ether;

    event Deposit(address indexed depositor, uint256 amount);
    event Withdrawal(address indexed withdrawer, uint256 amount);
    event AccessGranted(address indexed user);
    event AccessRevoked(address indexed user);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        // Grant initial access to owner
        hasAccess[_owner] = true;
        authorizedAddresses.push(_owner);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {
        require(newImplementation != address(0), "Invalid implementation");
    }

    modifier onlyAuthorized() {
        require(
            hasAccess[msg.sender] || msg.sender == owner(),
            "Not authorized"
        );
        _;
    }
    function getVersion() external pure returns (uint8) {
        return 255;
    }

    function deposit() public payable nonReentrant whenNotPaused {
        require(msg.value > 0, "Cannot deposit 0 ether");

        uint256 newBalance = balances[msg.sender] + msg.value;
        require(newBalance >= balances[msg.sender], "Overflow check");

        balances[msg.sender] = newBalance;
        totalDeposits += msg.value;

        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(
        uint256 amount
    ) external onlyAuthorized nonReentrant whenNotPaused {
        require(amount > 0, "Cannot withdraw 0 ether");
        require(
            amount <= MAX_WITHDRAWAL,
            "Amount exceeds maximum withdrawal limit"
        );
        require(
            address(this).balance >= amount,
            "Insufficient contract balance"
        );

        totalDeposits -= amount;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdrawal failed");

        emit Withdrawal(msg.sender, amount);
    }

    function grantAccess(address user) external onlyOwner {
        require(user != address(0), "Invalid address");
        require(!hasAccess[user], "Access already granted");

        hasAccess[user] = true;
        authorizedAddresses.push(user);

        emit AccessGranted(user);
    }

    function revokeAccess(address user) external onlyOwner {
        require(user != address(0), "Invalid address");
        require(hasAccess[user], "Access not granted");
        require(user != owner(), "Cannot revoke owner access");

        hasAccess[user] = false;

        for (uint256 i = 0; i < authorizedAddresses.length; i++) {
            if (authorizedAddresses[i] == user) {
                authorizedAddresses[i] = authorizedAddresses[
                    authorizedAddresses.length - 1
                ];
                authorizedAddresses.pop();
                break;
            }
        }

        emit AccessRevoked(user);
    }

    // View functions
    function getBalance(
        address account
    ) external view onlyAuthorized returns (uint256) {
        return balances[account];
    }

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getTotalDeposits() external view returns (uint256) {
        return totalDeposits;
    }

    function getAccessList() external view returns (address[] memory) {
        return authorizedAddresses;
    }

    // Admin functions
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    receive() external payable {
        deposit();
    }

    fallback() external payable {
        if (msg.value > 0) {
            deposit();
        } else {
            revert("Function does not exist");
        }
    }
}
