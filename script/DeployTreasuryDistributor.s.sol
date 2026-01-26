// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TreasuryDistributor} from '../src/contracts/TreasuryDistributor.sol';
import {VendingMachine} from '../src/contracts/VendingMachine.sol';
import {Script, console2} from 'forge-std/Script.sol';

contract DeployTreasuryDistributor is Script {
  function run() external returns (TreasuryDistributor distributor) {
    uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
    address deployer = vm.addr(deployerPrivateKey);

    // Get vending machine address from environment or use default for local testing
    address vendingMachineAddress = vm.envOr('VENDING_MACHINE', address(0));
    require(vendingMachineAddress != address(0), 'VENDING_MACHINE address not set');

    console2.log('Deploying TreasuryDistributor with deployer:', deployer);
    console2.log('VendingMachine address:', vendingMachineAddress);
    console2.log('Chain ID:', block.chainid);

    // Get vending machine instance
    VendingMachine vendingMachine = VendingMachine(vendingMachineAddress);

    vm.startBroadcast(deployerPrivateKey);

    // Deploy treasury distributor
    distributor = new TreasuryDistributor(vendingMachineAddress);

    // Set treasury distributor in vending machine
    vendingMachine.setTreasuryDistributor(address(distributor));

    vm.stopBroadcast();

    console2.log('===========================================');
    console2.log('TreasuryDistributor deployed at:', address(distributor));
    console2.log('Treasury role granted to distributor');
    console2.log('Cycle length: 30 days');
    console2.log('===========================================');

    return distributor;
  }
}
