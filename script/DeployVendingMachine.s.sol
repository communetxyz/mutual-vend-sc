// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VendingMachine} from '../src/contracts/VendingMachine.sol';
import {IVendingMachine} from '../src/interfaces/IVendingMachine.sol';
import {Script, console2} from 'forge-std/Script.sol';

contract DeployVendingMachine is Script {
  function run() external returns (VendingMachine vendingMachine, address voteToken) {
    uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
    address deployer = vm.addr(deployerPrivateKey);

    console2.log('Deploying VendingMachine with deployer:', deployer);
    console2.log('Chain ID:', block.chainid);

    // Setup configuration based on chain ID
    uint8 numTracks;
    uint256 maxStockPerTrack;
    string memory tokenName;
    string memory tokenSymbol;
    address[] memory acceptedTokens;
    IVendingMachine.Product[] memory initialProducts;
    uint256[] memory initialStocks;
    uint256[] memory initialPrices;

    if (block.chainid == 17_000) {
      // Holesky testnet configuration
      console2.log('Configuring for Holesky testnet...');
      numTracks = 10;
      maxStockPerTrack = 100;
      tokenName = 'Vending Machine Token';
      tokenSymbol = 'VMT';

      acceptedTokens = new address[](3);
      acceptedTokens[0] = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8; // Example USDC
      acceptedTokens[1] = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0; // Example USDT
      acceptedTokens[2] = 0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357; // Example DAI

      initialProducts = new IVendingMachine.Product[](3);
      initialProducts[0] = IVendingMachine.Product('Coca Cola', 'ipfs://QmCocaCola');
      initialProducts[1] = IVendingMachine.Product('Pepsi', 'ipfs://QmPepsi');
      initialProducts[2] = IVendingMachine.Product('Water', 'ipfs://QmWater');

      initialStocks = new uint256[](3);
      initialStocks[0] = 10;
      initialStocks[1] = 10;
      initialStocks[2] = 20;

      initialPrices = new uint256[](3);
      initialPrices[0] = 2 * 1e18; // $2
      initialPrices[1] = 2 * 1e18; // $2
      initialPrices[2] = 1 * 1e18; // $1
    } else if (block.chainid == 11_155_111) {
      // Sepolia testnet configuration
      console2.log('Configuring for Sepolia testnet...');
      numTracks = 10;
      maxStockPerTrack = 100;
      tokenName = 'Vending Machine Token';
      tokenSymbol = 'VMT';

      acceptedTokens = new address[](3);
      acceptedTokens[0] = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8; // Example USDC
      acceptedTokens[1] = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0; // Example USDT
      acceptedTokens[2] = 0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357; // Example DAI

      initialProducts = new IVendingMachine.Product[](3);
      initialProducts[0] = IVendingMachine.Product('Coca Cola', 'ipfs://QmCocaCola');
      initialProducts[1] = IVendingMachine.Product('Pepsi', 'ipfs://QmPepsi');
      initialProducts[2] = IVendingMachine.Product('Water', 'ipfs://QmWater');

      initialStocks = new uint256[](3);
      initialStocks[0] = 10;
      initialStocks[1] = 10;
      initialStocks[2] = 20;

      initialPrices = new uint256[](3);
      initialPrices[0] = 2 * 1e18; // $2
      initialPrices[1] = 2 * 1e18; // $2
      initialPrices[2] = 1 * 1e18; // $1
    } else {
      // Default configuration for local/unknown chains
      console2.log('Using default configuration for chain ID:', block.chainid);

      numTracks = 5;
      maxStockPerTrack = 50;
      tokenName = 'Test Vending Token';
      tokenSymbol = 'TVT';
      acceptedTokens = new address[](0);
      initialProducts = new IVendingMachine.Product[](0);
      initialStocks = new uint256[](0);
      initialPrices = new uint256[](0);
    }

    vm.startBroadcast(deployerPrivateKey);

    vendingMachine = new VendingMachine(
      numTracks, maxStockPerTrack, tokenName, tokenSymbol, acceptedTokens, initialProducts, initialStocks, initialPrices
    );

    voteToken = address(vendingMachine.voteToken());

    vm.stopBroadcast();

    console2.log('===========================================');
    console2.log('VendingMachine deployed at:', address(vendingMachine));
    console2.log('VoteToken deployed at:', voteToken);
    console2.log('Number of tracks:', numTracks);
    console2.log('Max stock per track:', maxStockPerTrack);
    console2.log('===========================================');

    // Log initial products if any
    if (initialProducts.length > 0) {
      console2.log('Initial products loaded:');
      for (uint256 i = 0; i < initialProducts.length; i++) {
        console2.log('  Track', i, ':', initialProducts[i].name);
      }
    }

    return (vendingMachine, voteToken);
  }
}
