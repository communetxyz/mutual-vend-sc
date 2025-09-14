// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VendingMachine} from '../src/contracts/VendingMachine.sol';
import {IVendingMachine} from '../src/interfaces/IVendingMachine.sol';
import {Script, console2} from 'forge-std/Script.sol';

contract DeployVendingMachine is Script {
  struct DeploymentConfig {
    uint8 numTracks;
    uint256 maxStockPerTrack;
    string tokenName;
    string tokenSymbol;
    address[] acceptedTokens;
    ProductConfig[] products;
  }

  struct ProductConfig {
    string name;
    string ipfsHash;
    uint256 stock;
    uint256 price;
  }

  function run() external returns (VendingMachine vendingMachine, address voteToken) {
    uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
    address deployer = vm.addr(deployerPrivateKey);

    console2.log('Deploying VendingMachine with deployer:', deployer);
    console2.log('Chain ID:', block.chainid);

    // Load configuration from JSON file
    DeploymentConfig memory config = loadConfig();

    // Prepare deployment parameters
    IVendingMachine.Product[] memory initialProducts = new IVendingMachine.Product[](config.products.length);
    uint256[] memory initialStocks = new uint256[](config.products.length);
    uint256[] memory initialPrices = new uint256[](config.products.length);

    for (uint256 i = 0; i < config.products.length; i++) {
      initialProducts[i] = IVendingMachine.Product(config.products[i].name, config.products[i].ipfsHash);
      initialStocks[i] = config.products[i].stock;
      initialPrices[i] = config.products[i].price;
    }

    vm.startBroadcast(deployerPrivateKey);

    vendingMachine = new VendingMachine(
      config.numTracks,
      config.maxStockPerTrack,
      config.tokenName,
      config.tokenSymbol,
      config.acceptedTokens,
      initialProducts,
      initialStocks,
      initialPrices
    );

    voteToken = address(vendingMachine.voteToken());

    vm.stopBroadcast();

    console2.log('===========================================');
    console2.log('VendingMachine deployed at:', address(vendingMachine));
    console2.log('VoteToken deployed at:', voteToken);
    console2.log('Number of tracks:', config.numTracks);
    console2.log('Max stock per track:', config.maxStockPerTrack);
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

  function loadConfig() internal view returns (DeploymentConfig memory) {
    string memory configPath = getConfigPath();
    console2.log('Loading configuration from:', configPath);

    string memory json = vm.readFile(configPath);

    DeploymentConfig memory config;
    config.numTracks = uint8(vm.parseJsonUint(json, '.numTracks'));
    config.maxStockPerTrack = vm.parseJsonUint(json, '.maxStockPerTrack');
    config.tokenName = vm.parseJsonString(json, '.tokenName');
    config.tokenSymbol = vm.parseJsonString(json, '.tokenSymbol');

    // Parse accepted tokens
    address[] memory tokens = vm.parseJsonAddressArray(json, '.acceptedTokens');
    config.acceptedTokens = tokens;

    // Parse products array - need to parse each field individually
    // First, determine the number of products
    uint256 numProducts = 0;
    while (true) {
      try vm.parseJsonString(json, string.concat('.products[', vm.toString(numProducts), '].name')) returns (
        string memory
      ) {
        numProducts++;
      } catch {
        break;
      }
    }

    // Parse each product individually
    config.products = new ProductConfig[](numProducts);
    for (uint256 i = 0; i < numProducts; i++) {
      string memory basePath = string.concat('.products[', vm.toString(i), ']');
      config.products[i].name = vm.parseJsonString(json, string.concat(basePath, '.name'));
      config.products[i].ipfsHash = vm.parseJsonString(json, string.concat(basePath, '.ipfsHash'));
      config.products[i].stock = vm.parseJsonUint(json, string.concat(basePath, '.stock'));
      config.products[i].price = vm.parseJsonUint(json, string.concat(basePath, '.price'));
    }

    validateConfig(config);

    return config;
  }

  function getConfigPath() internal view returns (string memory) {
    string memory configFile;

    if (block.chainid == 1) {
      configFile = 'mainnet.json';
    } else if (block.chainid == 17_000) {
      configFile = 'holesky.json';
    } else if (block.chainid == 31_337) {
      configFile = 'local.json';
    } else {
      // Allow override via environment variable
      try vm.envString('CONFIG_FILE') returns (string memory envConfig) {
        configFile = envConfig;
      } catch {
        configFile = 'local.json';
      }
    }

    return string(abi.encodePacked('config/', configFile));
  }

  function validateConfig(DeploymentConfig memory config) internal pure {
    require(config.numTracks > 0, 'Number of tracks must be greater than 0');
    require(config.maxStockPerTrack > 0, 'Max stock per track must be greater than 0');
    require(bytes(config.tokenName).length > 0, 'Token name cannot be empty');
    require(bytes(config.tokenSymbol).length > 0, 'Token symbol cannot be empty');
    require(config.products.length <= config.numTracks, 'Number of products cannot exceed number of tracks');

    for (uint256 i = 0; i < config.products.length; i++) {
      require(bytes(config.products[i].name).length > 0, 'Product name cannot be empty');
      require(bytes(config.products[i].ipfsHash).length > 0, 'Product IPFS hash cannot be empty');
      require(config.products[i].stock <= config.maxStockPerTrack, 'Product stock exceeds max stock per track');
      require(config.products[i].price > 0, 'Product price must be greater than 0');
    }
  }
}
