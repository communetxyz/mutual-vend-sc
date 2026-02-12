// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from 'forge-std/Script.sol';
import {VendingMachine} from '../src/contracts/VendingMachine.sol';
import {VoteToken} from '../src/contracts/VoteToken.sol';
// Lottery integration moved to BreadKit
import {ZKVerification} from '../src/contracts/ZKVerification.sol';
import {Crowdfunding} from '../src/contracts/Crowdfunding.sol';
import {IVendingMachine} from '../src/interfaces/IVendingMachine.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract MockUSDC is ERC20 {
  constructor() ERC20('Mock USDC', 'mUSDC') {
    _mint(msg.sender, 1_000_000e18);
  }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

contract DeployAllContracts is Script {
  function run() external {
    uint256 pk = vm.envUint('DEPLOYER_PRIVATE_KEY');
    vm.startBroadcast(pk);

    console2.log('=== Deploying Mutual Vend Full Platform ===');
    
    // Deploy mock stablecoin
    MockUSDC usdc = new MockUSDC();
    console2.log('MockUSDC:', address(usdc));

    // Prepare vending machine constructor args
    address[] memory tokens = new address[](1);
    tokens[0] = address(usdc);

    IVendingMachine.Product[] memory products = new IVendingMachine.Product[](3);
    products[0] = IVendingMachine.Product('Coca Cola', 'ipfs://QmCocaCola');
    products[1] = IVendingMachine.Product('Pepsi', 'ipfs://QmPepsi');
    products[2] = IVendingMachine.Product('Water', 'ipfs://QmWater');

    uint256[] memory stocks = new uint256[](3);
    stocks[0] = 8;
    stocks[1] = 8;
    stocks[2] = 8;

    uint256[] memory prices = new uint256[](3);
    prices[0] = 2e17; // 0.2 tokens
    prices[1] = 2e17;
    prices[2] = 1e17; // 0.1 tokens

    // Deploy vending machine (this also deploys VoteToken)
    VendingMachine machine = new VendingMachine(
      3, 10, 'Mutual Vend Token', 'MVT', tokens, products, stocks, prices
    );
    
    VoteToken voteToken = VoteToken(machine.voteToken());
    
    console2.log('VendingMachine:', address(machine));
    console2.log('VoteToken:', address(voteToken));

    // Lottery functionality integrated with BreadKit crowdstake.fun
    
    // Deploy ZK verification contract
    ZKVerification zkVerification = new ZKVerification();
    console2.log('ZKVerification:', address(zkVerification));
    
    // Deploy crowdfunding contract
    Crowdfunding crowdfunding = new Crowdfunding(address(voteToken));
    console2.log('Crowdfunding:', address(crowdfunding));
    
    // Grant minter role to crowdfunding so it can mint reward tokens
    voteToken.grantRole(voteToken.MINTER_ROLE(), address(crowdfunding));
    
    console2.log('=== Setup Example Data ===');
    
    // Create a sample crowdfunding campaign
    address[] memory campaignTokens = new address[](1);
    campaignTokens[0] = address(usdc);
    
    crowdfunding.createCampaign(
      "Expand Vending Network", 
      "Help us deploy 10 new vending machines across the city",
      "ipfs://QmCampaignImage",
      10000e18, // 10,000 USDC goal
      30 days,  // 30 day campaign
      campaignTokens
    );
    console2.log('Created crowdfunding campaign 1');

    console2.log('=== All Contracts Deployed Successfully! ===');
    
    vm.stopBroadcast();
  }
}