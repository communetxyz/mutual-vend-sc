// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VendingMachine} from '../src/contracts/VendingMachine.sol';
import {IVendingMachine} from '../src/interfaces/IVendingMachine.sol';
import {Script, console2} from 'forge-std/Script.sol';

contract UpdateProducts is Script {
  struct ProductUpdateConfig {
    ProductUpdate[] productUpdates;
  }

  struct ProductUpdate {
    uint8 trackId;
    string name;
    string imageURI;
    uint256 stock; // current stock to maintain
  }

  function run() external {
    address vendingMachineAddress = vm.envAddress('VENDING_MACHINE_ADDRESS');
    uint256 operatorPrivateKey = vm.envUint('PRIVATE_KEY');
    address operator = vm.addr(operatorPrivateKey);

    console2.log('===========================================');
    console2.log('Updating products for VendingMachine at:', vendingMachineAddress);
    console2.log('Operator:', operator);
    console2.log('Chain ID:', block.chainid);
    console2.log('===========================================');

    VendingMachine vendingMachine = VendingMachine(vendingMachineAddress);

    ProductUpdateConfig memory config = loadProductUpdateConfig();

    vm.startBroadcast(operatorPrivateKey);

    for (uint256 i = 0; i < config.productUpdates.length; i++) {
      ProductUpdate memory update = config.productUpdates[i];
      
      // Get current track info
      IVendingMachine.Track memory trackBefore = vendingMachine.getTrack(update.trackId);
      console2.log('Track %s current product: %s', update.trackId, trackBefore.product.name);
      console2.log('Current image: %s', trackBefore.product.imageURI);
      
      // If stock is 0 in config, use current stock
      uint256 stockToSet = update.stock > 0 ? update.stock : trackBefore.stock;
      
      // Create new product
      IVendingMachine.Product memory newProduct = IVendingMachine.Product({
        name: update.name,
        imageURI: update.imageURI
      });
      
      // Update the track with new product info
      vendingMachine.loadTrack(update.trackId, newProduct, stockToSet);
      
      IVendingMachine.Track memory trackAfter = vendingMachine.getTrack(update.trackId);
      console2.log('Track %s new product: %s', update.trackId, trackAfter.product.name);
      console2.log('New image: %s', trackAfter.product.imageURI);
      console2.log('Stock maintained at: %s', trackAfter.stock);
      console2.log('---');
    }

    vm.stopBroadcast();

    console2.log('===========================================');
    console2.log('Product update operation completed successfully');
    console2.log('Total tracks updated:', config.productUpdates.length);
    console2.log('===========================================');
  }

  function loadProductUpdateConfig() internal view returns (ProductUpdateConfig memory) {
    string memory configPath = getConfigPath();
    console2.log('Loading product update configuration from:', configPath);

    string memory json = vm.readFile(configPath);

    ProductUpdateConfig memory config;

    uint256 numUpdates = 0;
    while (true) {
      try vm.parseJsonUint(json, string.concat('.productUpdates[', vm.toString(numUpdates), '].trackId')) returns (
        uint256
      ) {
        numUpdates++;
      } catch {
        break;
      }
    }

    config.productUpdates = new ProductUpdate[](numUpdates);
    for (uint256 i = 0; i < numUpdates; i++) {
      string memory basePath = string.concat('.productUpdates[', vm.toString(i), ']');
      config.productUpdates[i].trackId = uint8(vm.parseJsonUint(json, string.concat(basePath, '.trackId')));
      config.productUpdates[i].name = vm.parseJsonString(json, string.concat(basePath, '.name'));
      config.productUpdates[i].imageURI = vm.parseJsonString(json, string.concat(basePath, '.imageURI'));
      
      // Stock is optional, default to 0 which means maintain current stock
      try vm.parseJsonUint(json, string.concat(basePath, '.stock')) returns (uint256 stock) {
        config.productUpdates[i].stock = stock;
      } catch {
        config.productUpdates[i].stock = 0;
      }
    }

    validateConfig(config);

    return config;
  }

  function getConfigPath() internal view returns (string memory) {
    try vm.envString('PRODUCT_CONFIG_FILE') returns (string memory envConfig) {
      return envConfig;
    } catch {
      return 'config/product_update.json';
    }
  }

  function validateConfig(ProductUpdateConfig memory config) internal pure {
    require(config.productUpdates.length > 0, 'No product updates provided');
    
    for (uint256 i = 0; i < config.productUpdates.length; i++) {
      require(
        bytes(config.productUpdates[i].name).length > 0 || 
        bytes(config.productUpdates[i].imageURI).length > 0,
        'Product must have name or imageURI'
      );
    }
  }
}