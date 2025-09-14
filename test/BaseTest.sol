// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VendingMachine} from '../src/contracts/VendingMachine.sol';
import {VoteToken} from '../src/contracts/VoteToken.sol';
import {IVendingMachine} from '../src/interfaces/IVendingMachine.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {Test} from 'forge-std/Test.sol';

contract MockStablecoin is ERC20 {
  constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

abstract contract BaseTest is Test {
  // Deployment config struct
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

  // Core contracts
  VendingMachine public vendingMachine;
  VoteToken public voteToken;

  // Mock tokens for testing
  MockStablecoin public usdc;
  MockStablecoin public usdt;
  MockStablecoin public dai;

  // Test addresses
  address public owner = makeAddr('owner');
  address public operator = makeAddr('operator');
  address public treasury = makeAddr('treasury');
  address public customer = makeAddr('customer');
  address public nonOperator = makeAddr('nonOperator');
  address public nonTreasury = makeAddr('nonTreasury');

  // Default config values
  uint8 constant DEFAULT_NUM_TRACKS = 3;
  uint256 constant DEFAULT_MAX_STOCK = 50;

  function setUp() public virtual {
    // Deploy mock tokens
    vm.startPrank(owner);
    usdc = new MockStablecoin('USD Coin', 'USDC');
    usdt = new MockStablecoin('Tether', 'USDT');
    dai = new MockStablecoin('Dai', 'DAI');
    vm.stopPrank();

    // Deploy vending machine with config
    DeploymentConfig memory config = getDeploymentConfig();
    deployVendingMachine(config);

    // Setup roles
    vm.startPrank(owner);
    vendingMachine.grantRole(vendingMachine.OPERATOR_ROLE(), operator);
    vendingMachine.grantRole(vendingMachine.TREASURY_ROLE(), treasury);
    vm.stopPrank();
  }

  function getDeploymentConfig() internal virtual returns (DeploymentConfig memory) {
    // Default config for tests - can be overridden in child contracts
    DeploymentConfig memory config;
    config.numTracks = DEFAULT_NUM_TRACKS;
    config.maxStockPerTrack = DEFAULT_MAX_STOCK;
    config.tokenName = 'Vending Machine Token';
    config.tokenSymbol = 'VMT';

    // Setup accepted tokens
    config.acceptedTokens = new address[](3);
    config.acceptedTokens[0] = address(usdc);
    config.acceptedTokens[1] = address(usdt);
    config.acceptedTokens[2] = address(dai);

    // No initial products by default
    config.products = new ProductConfig[](0);

    return config;
  }

  function deployVendingMachine(DeploymentConfig memory config) internal {
    // Prepare deployment parameters
    IVendingMachine.Product[] memory initialProducts = new IVendingMachine.Product[](config.products.length);
    uint256[] memory initialStocks = new uint256[](config.products.length);
    uint256[] memory initialPrices = new uint256[](config.products.length);

    for (uint256 i = 0; i < config.products.length; i++) {
      initialProducts[i] = IVendingMachine.Product(config.products[i].name, config.products[i].ipfsHash);
      initialStocks[i] = config.products[i].stock;
      initialPrices[i] = config.products[i].price;
    }

    vm.prank(owner);
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

    voteToken = vendingMachine.voteToken();
  }

  // Helper function to load config from JSON (for integration tests)
  function loadConfigFromJson(string memory filename) internal view returns (DeploymentConfig memory) {
    string memory root = vm.projectRoot();
    string memory path = string(abi.encodePacked(root, '/config/', filename, '.json'));
    string memory json = vm.readFile(path);

    DeploymentConfig memory config;
    config.numTracks = uint8(vm.parseJsonUint(json, '.numTracks'));
    config.maxStockPerTrack = vm.parseJsonUint(json, '.maxStockPerTrack');
    config.tokenName = vm.parseJsonString(json, '.tokenName');
    config.tokenSymbol = vm.parseJsonString(json, '.tokenSymbol');

    // Parse accepted tokens
    address[] memory tokens;
    try vm.parseJsonAddressArray(json, '.acceptedTokens') returns (address[] memory parsedTokens) {
      tokens = parsedTokens;
    } catch {
      tokens = new address[](0);
    }
    config.acceptedTokens = tokens;

    // Parse products - simplified for testing
    // In a real scenario, you'd parse the full products array
    config.products = new ProductConfig[](0);

    return config;
  }
}
