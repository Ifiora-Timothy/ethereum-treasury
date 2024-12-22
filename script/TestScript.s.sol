// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/OptimisedTreasury2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract DeployScript is Script {
    address public proxyAddress;

    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);
        //privte key to use  0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

        // Deploy implementation
        address proxyAddress = 0x09635F643e140090A9A8Dcd712eD6285858ceBef;
        OptimizedTreasury2 implementation = new OptimizedTreasury2();

        // Upgrade proxy to new implementation
        UUPSUpgradeable proxy = UUPSUpgradeable(proxyAddress);
        proxy.upgradeToAndCall(
            address(implementation),
            abi.encodeWithSignature("getVersion()")
        );

        //verify the get version function
        // Call getVersion directly from the proxy contract (after upgrade)
        (bool success, bytes memory data) = proxyAddress.call(
            abi.encodeWithSignature("getVersion()")
        );
        require(success, "Failed to call getVersion");

        // Decode the result and log the version
        uint8 version = abi.decode(data, (uint8));
        console.log("Contract Version:", version);

        vm.stopBroadcast();
        console.log("Owner:", deployerAddress);
        return address(implementation);
    }
}
