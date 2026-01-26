// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VendingMachine} from '../src/contracts/VendingMachine.sol';
import {IVendingMachine} from '../src/interfaces/IVendingMachine.sol';
import {Script, console2} from 'forge-std/Script.sol';

contract RestockVendingMachine is Script {
  struct RestockConfig {
    RestockItem[] restockItems;
  }

  struct RestockItem {
    uint8 trackId;
    uint256 additionalStock;
  }

  function run() external {
    address vendingMachineAddress = vm.envAddress('VENDING_MACHINE_ADDRESS');
    uint256 operatorPrivateKey = vm.envUint('PRIVATE_KEY');
    address operator = vm.addr(operatorPrivateKey);

    console2.log('===========================================');
    console2.log('Restocking VendingMachine at:', vendingMachineAddress);
    console2.log('Operator:', operator);
    console2.log('Chain ID:', block.chainid);
    console2.log('===========================================');

    VendingMachine vendingMachine = VendingMachine(vendingMachineAddress);

    RestockConfig memory config = loadRestockConfig();

    vm.startBroadcast(operatorPrivateKey);

    for (uint256 i = 0; i < config.restockItems.length; i++) {
      RestockItem memory item = config.restockItems[i];
      
      uint256 currentStock = vendingMachine.getTrackInventory(item.trackId);
      console2.log('Track %s current stock: %s', item.trackId, currentStock);
      
      vendingMachine.restockTrack(item.trackId, item.additionalStock);
      
      uint256 newStock = vendingMachine.getTrackInventory(item.trackId);
      console2.log('Track %s restocked with %s units', item.trackId, item.additionalStock);
      console2.log('Track %s new stock: %s', item.trackId, newStock);
      console2.log('---');
    }

    vm.stopBroadcast();

    console2.log('===========================================');
    console2.log('Restock operation completed successfully');
    console2.log('Total tracks restocked:', config.restockItems.length);
    console2.log('===========================================');
  }

  function loadRestockConfig() internal view returns (RestockConfig memory) {
    string memory configPath = getConfigPath();
    console2.log('Loading restock configuration from:', configPath);

    string memory json = vm.readFile(configPath);

    RestockConfig memory config;

    uint256 numItems = 0;
    while (true) {
      try vm.parseJsonUint(json, string.concat('.restockItems[', vm.toString(numItems), '].trackId')) returns (
        uint256
      ) {
        numItems++;
      } catch {
        break;
      }
    }

    config.restockItems = new RestockItem[](numItems);
    for (uint256 i = 0; i < numItems; i++) {
      string memory basePath = string.concat('.restockItems[', vm.toString(i), ']');
      config.restockItems[i].trackId = uint8(vm.parseJsonUint(json, string.concat(basePath, '.trackId')));
      config.restockItems[i].additionalStock = vm.parseJsonUint(json, string.concat(basePath, '.additionalStock'));
    }

    validateConfig(config);

    return config;
  }

  function getConfigPath() internal view returns (string memory) {
    try vm.envString('RESTOCK_CONFIG_FILE') returns (string memory envConfig) {
      return envConfig;
    } catch {
      return 'config/restock.json';
    }
  }

  function validateConfig(RestockConfig memory config) internal pure {
    require(config.restockItems.length > 0, 'No restock items provided');
    
    for (uint256 i = 0; i < config.restockItems.length; i++) {
      require(config.restockItems[i].additionalStock > 0, 'Additional stock must be greater than 0');
    }
  }
}