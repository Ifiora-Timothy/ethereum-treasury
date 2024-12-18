// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {CentralWallet} from "../src/CentralWallet.sol";
import {CentralWalletV2} from "../src/CentralWalletV2.sol";
import {Treasury} from "../src/TreasuryContract.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract CounterScript is Script {
    CentralWallet public centralWallet;
    CentralWalletV2 public centralWalletV2;
 
    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public proxy;
    Treasury public treasury;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        centralWallet = new CentralWallet();
        centralWalletV2 = new CentralWalletV2();
        proxy = new TransparentUpgradeableProxy(address(centralWallet), address(proxyAdmin), "");
        treasury = new Treasury(address(proxy));
     
        vm.stopBroadcast();
    }
}
