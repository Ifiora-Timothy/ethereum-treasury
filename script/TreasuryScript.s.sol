// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import "../src/OptimisedTreasury.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployScript is Script {
    // Track total gas used across all operations
    uint256 private totalGasUsed = 0;

    function setUp() public view {
        require(
            keccak256(abi.encodePacked(vm.envOr("NETWORK", string("")))) !=
                keccak256(abi.encodePacked("")),
            "NETWORK must be set"
        );
        require(
            keccak256(abi.encodePacked(vm.envOr("PRIVATE_KEY", string("")))) !=
                keccak256(abi.encodePacked("")),
            "PRIVATE_KEY must be set"
        );
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        string memory network = vm.envString("NETWORK");

        console.log("Deploying to network:", network);
        console.log("Deployer address:", deployerAddress);

        // Get current gas price with priority fee
        uint256 baseGasPrice = block.basefee;
        uint256 priorityFee = 1 gwei; // Adjust based on network conditions
        uint256 totalGasPrice = baseGasPrice + priorityFee;

        console.log("\nCurrent base gas price:", baseGasPrice, "wei");
        console.log("Priority fee:", priorityFee, "wei");
        console.log("Total gas price:", totalGasPrice, "wei");
        console.log("In gwei:", totalGasPrice / 1e9);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Treasury implementation
        uint256 gasBefore = gasleft();
        OptimizedTreasury treasuryImplementation = new OptimizedTreasury();
        uint256 operationGas = gasBefore - gasleft();
        totalGasUsed += operationGas;
        console.log(
            "\nTreasury Implementation deployed at:",
            address(treasuryImplementation)
        );
        console.log("Gas used for Treasury implementation:", operationGas);

        // 2. Deploy Treasury proxy with initialization
        gasBefore = gasleft();
        bytes memory initData = abi.encodeWithSelector(
            OptimizedTreasury.initialize.selector,
            deployerAddress
        );
        ERC1967Proxy treasuryProxy = new ERC1967Proxy(
            address(treasuryImplementation),
            initData
        );
        operationGas = gasBefore - gasleft();
        totalGasUsed += operationGas;
        console.log("\nTreasury Proxy deployed at:", address(treasuryProxy));
        console.log(
            "Gas used for Treasury proxy and initialization:",
            operationGas
        );

        // Note: No need to grant access to deployer as it's done in initialization

        vm.stopBroadcast();

        // Log total costs with detailed breakdown
        console.log("\n=== Cost Summary ===");
        console.log("Total gas used:", totalGasUsed);
        uint256 estimatedBaseCost = totalGasUsed * baseGasPrice;
        uint256 estimatedPriorityFee = totalGasUsed * priorityFee;
        uint256 estimatedTotalCost = totalGasUsed * totalGasPrice;

        console.log("\nBase cost in wei:", estimatedBaseCost);
        console.log("Priority fee cost in wei:", estimatedPriorityFee);
        console.log("Total estimated cost in wei:", estimatedTotalCost);

        console.log("\nBase cost in ETH:", estimatedBaseCost / 1e18);
        console.log("Priority fee cost in ETH:", estimatedPriorityFee / 1e18);
        console.log("Total estimated cost in ETH:", estimatedTotalCost / 1e18);

        // Log deployment verification information
        console.log("\n=== Verification Information ===");
        console.log(
            "Implementation Contract:",
            address(treasuryImplementation)
        );
        console.log("Proxy Contract:", address(treasuryProxy));
        console.log("Owner:", deployerAddress);
    }
}
