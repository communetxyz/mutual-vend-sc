// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from 'forge-std/Script.sol';
import {VendingMachine} from '../src/contracts/VendingMachine.sol';
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

contract DeploySepolia is Script {
  function run() external {
    uint256 pk = vm.envUint('DEPLOYER_PRIVATE_KEY');
    vm.startBroadcast(pk);

    // Deploy mock stablecoin
    MockUSDC usdc = new MockUSDC();
    console2.log('MockUSDC:', address(usdc));

    // Prepare constructor args
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
    prices[2] = 1e17;

    VendingMachine machine = new VendingMachine(
      3, 10, 'Mutual Vend Token', 'MVT', tokens, products, stocks, prices
    );

    console2.log('VendingMachine:', address(machine));
    console2.log('VoteToken:', address(machine.voteToken()));

    vm.stopBroadcast();
  }
}
