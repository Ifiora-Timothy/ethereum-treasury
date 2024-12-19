// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract CentralWalletV2 {
    address public owner;
    mapping(address => uint256) public balances;

    constructor() {
        owner = msg.sender;
    }

    function deposit() public payable {
        balances[msg.sender] += msg.value;
        //show that this is a different central wallet
    }

    function withdraw(uint256 amount) public {
        require(balances[msg.sender] >= amount, "Insufficient v2 balance");
        balances[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
    }
}
