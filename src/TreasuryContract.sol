// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

interface IProxyAdmin {
    function upgrade(ITransparentUpgradeableProxy proxy, address implementation) external;}

 

contract Treasury is Ownable, ReentrancyGuard {
    address public proxyAddress;
    bool public isInitialized;
     IProxyAdmin public proxyAdmin;
    mapping(address => bool) public hasAccess;
   constructor(address _proxyAdmin) Ownable(msg.sender) {
        proxyAdmin = IProxyAdmin(_proxyAdmin);
    }
    event CentralWalletInitialized(address centralWalletAddress);
    event AccessGranted(address user);
    event AccessRevoked(address user);
    
    modifier onlyAuthorized() {
        require(hasAccess[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }

    function initializeCentralWallet(address _centralWalletImplementation) external onlyOwner {
        require(!isInitialized, "CentralWallet already initialized");
         TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            _centralWalletImplementation, 
            address(this),  // admin
            ""  // no initialization data
        );
        proxyAddress = address(proxy);
        isInitialized = true;
        emit CentralWalletInitialized(proxyAddress);
    }

    function grantAccess(address _user) external onlyOwner {
        require(!hasAccess[_user], "Access already granted");
        hasAccess[_user] = true;
        emit AccessGranted(_user);
    }

    function revokeAccess(address _user) external onlyOwner {
        require(hasAccess[_user], "Access not granted");
        hasAccess[_user] = false;
        emit AccessRevoked(_user);
    }

    function deposit() external payable onlyAuthorized nonReentrant {
        require(isInitialized, "CentralWallet not initialized");
        (bool success,) = proxyAddress.delegatecall(abi.encodeWithSignature("deposit()"));
        require(success, "Deposit failed");
    }

    function withdraw(uint256 amount) external onlyAuthorized nonReentrant {
        require(isInitialized, "CentralWallet not initialized");
        (bool success,) = proxyAddress.delegatecall(abi.encodeWithSignature("withdraw(uint256)", amount));
        require(success, "Withdrawal failed");
    }

     function upgradeTo(address _newImplementation) external onlyOwner {
        require(_newImplementation != address(0), "Invalid implementation");
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(proxyAddress), _newImplementation);
    }
}