// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VendingMachine} from '../src/contracts/VendingMachine.sol';
import {IVendingMachine} from '../src/interfaces/IVendingMachine.sol';
import {Script, console2} from 'forge-std/Script.sol';

contract UpdatePrices is Script {
  struct PriceUpdateConfig {
    PriceUpdate[] priceUpdates;
  }

  struct PriceUpdate {
    uint8 trackId;
    uint256 newPrice;
  }

  function run() external {
    address vendingMachineAddress = vm.envAddress('VENDING_MACHINE_ADDRESS');
    uint256 operatorPrivateKey = vm.envUint('PRIVATE_KEY');
    address operator = vm.addr(operatorPrivateKey);

    console2.log('===========================================');
    console2.log('Updating prices for VendingMachine at:', vendingMachineAddress);
    console2.log('Operator:', operator);
    console2.log('Chain ID:', block.chainid);
    console2.log('===========================================');

    VendingMachine vendingMachine = VendingMachine(vendingMachineAddress);

    PriceUpdateConfig memory config = loadPriceUpdateConfig();

    vm.startBroadcast(operatorPrivateKey);

    for (uint256 i = 0; i < config.priceUpdates.length; i++) {
      PriceUpdate memory update = config.priceUpdates[i];
      
      IVendingMachine.Track memory trackBefore = vendingMachine.getTrack(update.trackId);
      console2.log('Track %s current price: %s USD', update.trackId, trackBefore.price / 1e18);
      
      vendingMachine.setTrackPrice(update.trackId, update.newPrice);
      
      IVendingMachine.Track memory trackAfter = vendingMachine.getTrack(update.trackId);
      console2.log('Track %s new price: %s USD', update.trackId, trackAfter.price / 1e18);
      console2.log('Product: %s', trackAfter.product.name);
      console2.log('---');
    }

    vm.stopBroadcast();

    console2.log('===========================================');
    console2.log('Price update operation completed successfully');
    console2.log('Total tracks updated:', config.priceUpdates.length);
    console2.log('===========================================');
  }

  function loadPriceUpdateConfig() internal view returns (PriceUpdateConfig memory) {
    string memory configPath = getConfigPath();
    console2.log('Loading price update configuration from:', configPath);

    string memory json = vm.readFile(configPath);

    PriceUpdateConfig memory config;

    uint256 numUpdates = 0;
    while (true) {
      try vm.parseJsonUint(json, string.concat('.priceUpdates[', vm.toString(numUpdates), '].trackId')) returns (
        uint256
      ) {
        numUpdates++;
      } catch {
        break;
      }
    }

    config.priceUpdates = new PriceUpdate[](numUpdates);
    for (uint256 i = 0; i < numUpdates; i++) {
      string memory basePath = string.concat('.priceUpdates[', vm.toString(i), ']');
      config.priceUpdates[i].trackId = uint8(vm.parseJsonUint(json, string.concat(basePath, '.trackId')));
      config.priceUpdates[i].newPrice = vm.parseJsonUint(json, string.concat(basePath, '.newPrice'));
    }

    validateConfig(config);

    return config;
  }

  function getConfigPath() internal view returns (string memory) {
    try vm.envString('PRICE_CONFIG_FILE') returns (string memory envConfig) {
      return envConfig;
    } catch {
      return 'config/price_update.json';
    }
  }

  function validateConfig(PriceUpdateConfig memory config) internal pure {
    require(config.priceUpdates.length > 0, 'No price updates provided');
    
    for (uint256 i = 0; i < config.priceUpdates.length; i++) {
      require(config.priceUpdates[i].newPrice > 0, 'Price must be greater than 0');
    }
  }
}