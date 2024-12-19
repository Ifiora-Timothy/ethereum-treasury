// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

interface ICentralWallet {
    function upgradeTo(address newImplementation) external;
    function initialize(address _treasury) external;
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

contract Treasury is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable
{
    address public centralWallet;
    bool private _initialized;
    mapping(address => bool) public hasAccess;
    uint256 private constant MAX_WITHDRAWAL = 100 ether;
    // Track the original sender for forwarded calls
    address private _originalSender;

    event CentralWalletInitialized(address centralWalletAddress);
    event CentralWalletUpgraded(address centralWalletAddress);
    event AccessGranted(address indexed user);
    event AccessRevoked(address indexed user);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function getOriginalSender() external view returns (address) {
        require(msg.sender == centralWallet, "Unauthorized");
        return _originalSender;
    }

    function _setOriginalSender() private {
        _originalSender = msg.sender;
    }

    function initialize(address _owner) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal view override onlyOwner {
        require(newImplementation != address(0), "Invalid implementation");
    }

    function initializeCentralWallet(
        address _centralWalletImplementation
    ) external onlyOwner {
        require(!_initialized, "Already initialized");
        require(
            _centralWalletImplementation != address(0),
            "Invalid implementation"
        );
        require(
            _centralWalletImplementation.code.length > 0,
            "Implementation must be contract"
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            _centralWalletImplementation,
            abi.encodeWithSelector(
                ICentralWallet.initialize.selector,
                address(this)
            )
        );

        centralWallet = address(proxy);
        _initialized = true;

        emit CentralWalletInitialized(centralWallet);
    }

    function _forwardToWallet(uint256 amount) internal {
        require(amount > 0, "Cannot forward zero value");
        require(centralWallet != address(0), "Central wallet not initialized");

        _setOriginalSender();

        (bool success, bytes memory returnData) = centralWallet.call{
            value: amount
        }(abi.encodeWithSelector(ICentralWallet.deposit.selector));

        delete _originalSender; // Clean up storage

        if (!success) {
            if (returnData.length > 0) {
                assembly {
                    revert(add(returnData, 32), mload(returnData))
                }
            } else {
                revert("Forward to wallet failed");
            }
        }
    }

    function grantAccess(address _user) external onlyOwner {
        require(_user != address(0), "Invalid address");
        require(!hasAccess[_user], "Access already granted");

        hasAccess[_user] = true;
        emit AccessGranted(_user);
    }

    function revokeAccess(address _user) external onlyOwner {
        require(_user != address(0), "Invalid address");
        require(hasAccess[_user], "Access not granted");

        hasAccess[_user] = false;
        emit AccessRevoked(_user);
    }

    modifier onlyAuthorized() {
        require(
            hasAccess[msg.sender] || msg.sender == owner(),
            "Not authorized"
        );
        _;
    }

    function deposit()
        external
        payable
        onlyAuthorized
        nonReentrant
        whenNotPaused
    {
        _forwardToWallet(msg.value);
    }

    function withdraw(
        uint256 amount
    ) external onlyAuthorized nonReentrant whenNotPaused {
        require(
            amount <= MAX_WITHDRAWAL,
            "Amount exceeds maximum withdrawal limit"
        );
        _setOriginalSender();

        (bool success, bytes memory returnData) = centralWallet.call{value: 0}(
            abi.encodeWithSelector(ICentralWallet.withdraw.selector, amount)
        );
        delete _originalSender; // Clean up storage

        if (!success) {
            if (returnData.length > 0) {
                assembly {
                    revert(add(returnData, 32), mload(returnData))
                }
            } else {
                revert("Withdrawal failed");
            }
        }
    }

    function upgradeCentralWallet(
        address _newImplementation
    ) external onlyOwner whenPaused {
        require(_newImplementation != address(0), "Invalid implementation");
        require(
            _newImplementation.code.length > 0,
            "Implementation must be contract"
        );

        (bool success, ) = centralWallet.call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)",
                _newImplementation,
                ""
            )
        );
        require(success, "Upgrade failed");

        emit CentralWalletUpgraded(_newImplementation);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    receive() external payable {
        _forwardToWallet(msg.value);
    }

    fallback() external payable {
        _forwardToWallet(msg.value);
    }
}
