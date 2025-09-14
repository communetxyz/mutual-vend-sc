// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VendingMachine} from '../src/contracts/VendingMachine.sol';
import {IVendingMachine} from '../src/interfaces/IVendingMachine.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Script, console2} from 'forge-std/Script.sol';

contract PurchaseFromGnosis is Script {
  // Gnosis token address from config
  address constant GNOSIS_TOKEN = 0xa555d5344f6FB6c65da19e403Cb4c1eC4a1a5Ee3;

  function run() external {
    // Get environment variables
    uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
    address deployer = vm.addr(deployerPrivateKey);

    // Get the VendingMachine address from environment or use a default
    address vendingMachineAddress =
      vm.envOr('VENDING_MACHINE_ADDRESS', address(0x914b0Ac88384A9Ccb7D0d61d35e5EDee60860900));

    console2.log('===========================================');
    console2.log('Purchasing from VendingMachine on Gnosis');
    console2.log('===========================================');
    console2.log('Purchaser:', deployer);
    console2.log('VendingMachine:', vendingMachineAddress);
    console2.log('Token:', GNOSIS_TOKEN);

    vm.startBroadcast(deployerPrivateKey);

    // Get references to contracts
    IERC20 token = IERC20(GNOSIS_TOKEN);
    VendingMachine vendingMachine = VendingMachine(vendingMachineAddress);

    // Check token balance
    uint256 tokenBalance = token.balanceOf(deployer);
    console2.log('Token Balance:', tokenBalance);

    if (tokenBalance == 0) {
      console2.log('Warning: No token balance');
    }

    // Get track information for all 3 tracks
    for (uint8 trackId = 0; trackId < 3; trackId++) {
      IVendingMachine.Track memory track = vendingMachine.getTrack(trackId);

      console2.log('===========================================');
      console2.log('Track', trackId, 'Information:');
      console2.log('Product:', track.product.name);
      console2.log('Stock:', track.stock);
      console2.log('Price:', track.price);
    }

    // Purchase from track 0 (Coca Cola)
    uint8 trackToPurchase = 0;
    IVendingMachine.Track memory selectedTrack = vendingMachine.getTrack(trackToPurchase);

    console2.log('===========================================');
    console2.log('Attempting to purchase from Track', trackToPurchase);
    console2.log('Product:', selectedTrack.product.name);
    console2.log('Price:', selectedTrack.price);

    if (selectedTrack.stock == 0) {
      console2.log('Track is out of stock!');
      vm.stopBroadcast();
      return;
    }

    if (tokenBalance < selectedTrack.price) {
      console2.log('Insufficient token balance for purchase');
      console2.log('Required:', selectedTrack.price);
      console2.log('Available:', tokenBalance);
      vm.stopBroadcast();
      return;
    }

    // Check current allowance
    uint256 currentAllowance = token.allowance(deployer, vendingMachineAddress);
    console2.log('Current token allowance:', currentAllowance);

    // Approve VendingMachine to spend tokens if needed
    if (currentAllowance < selectedTrack.price) {
      console2.log('Approving VendingMachine to spend', selectedTrack.price, 'tokens...');
      bool approveSuccess = token.approve(vendingMachineAddress, selectedTrack.price);
      require(approveSuccess, 'Token approval failed');
      console2.log('Approval successful!');
    } else {
      console2.log('Sufficient allowance already exists');
    }

    // Make the purchase
    console2.log('Purchasing from track', trackToPurchase, '...');
    vendingMachine.vendFromTrack(trackToPurchase, GNOSIS_TOKEN, deployer);
    console2.log('Purchase successful!');

    // Check new balance and vote tokens received
    uint256 newTokenBalance = token.balanceOf(deployer);
    console2.log('New Token Balance:', newTokenBalance);
    console2.log('Tokens Spent:', tokenBalance - newTokenBalance);

    // Get vote token balance
    address voteTokenAddress = address(vendingMachine.voteToken());
    IERC20 voteToken = IERC20(voteTokenAddress);
    uint256 voteTokenBalance = voteToken.balanceOf(deployer);
    console2.log('Vote Tokens Received:', voteTokenBalance);

    vm.stopBroadcast();

    console2.log('===========================================');
    console2.log('Purchase completed successfully!');
    console2.log('===========================================');
  }
}
