// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VendingMachine} from '../src/contracts/VendingMachine.sol';
import {IVendingMachine} from '../src/interfaces/IVendingMachine.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Script, console2} from 'forge-std/Script.sol';

contract PurchaseFromVendingMachine is Script {
  // Sepolia USDC token address
  address constant SEPOLIA_USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

  function run() external {
    // Get environment variables
    uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
    address deployer = vm.addr(deployerPrivateKey);

    // Get the VendingMachine address from environment or use a default
    address vendingMachineAddress = vm.envOr('VENDING_MACHINE_ADDRESS', address(0));
    require(vendingMachineAddress != address(0), 'VENDING_MACHINE_ADDRESS not set');

    console2.log('===========================================');
    console2.log('Purchasing from VendingMachine');
    console2.log('===========================================');
    console2.log('Purchaser:', deployer);
    console2.log('VendingMachine:', vendingMachineAddress);
    console2.log('USDC Token:', SEPOLIA_USDC);

    vm.startBroadcast(deployerPrivateKey);

    // Get references to contracts
    IERC20 usdc = IERC20(SEPOLIA_USDC);
    VendingMachine vendingMachine = VendingMachine(vendingMachineAddress);

    // Check USDC balance
    uint256 usdcBalance = usdc.balanceOf(deployer);
    console2.log('USDC Balance:', usdcBalance);
    require(usdcBalance > 0, 'No USDC balance');

    // Get track information
    uint8 trackId = 0; // Track 1 (0-indexed)
    IVendingMachine.Track memory track = vendingMachine.getTrack(trackId);

    console2.log('===========================================');
    console2.log('Track Information:');
    console2.log('Track ID:', trackId);
    console2.log('Product:', track.product.name);
    console2.log('Stock:', track.stock);
    console2.log('Price (in USDC):', track.price);
    console2.log('===========================================');

    require(track.stock > 0, 'Track is out of stock');
    require(usdcBalance >= track.price, 'Insufficient USDC balance for purchase');

    // Check current allowance
    uint256 currentAllowance = usdc.allowance(deployer, vendingMachineAddress);
    console2.log('Current USDC allowance:', currentAllowance);

    // Approve VendingMachine to spend USDC if needed
    if (currentAllowance < track.price) {
      console2.log('Approving VendingMachine to spend', track.price, 'USDC...');
      bool approveSuccess = usdc.approve(vendingMachineAddress, track.price);
      require(approveSuccess, 'USDC approval failed');
      console2.log('Approval successful!');
    } else {
      console2.log('Sufficient allowance already exists');
    }

    // Make the purchase
    console2.log('Purchasing from track', trackId, '...');
    vendingMachine.vendFromTrack(trackId, SEPOLIA_USDC, deployer);
    console2.log('Purchase successful!');

    // Check new balance and vote tokens received
    uint256 newUsdcBalance = usdc.balanceOf(deployer);
    console2.log('New USDC Balance:', newUsdcBalance);
    console2.log('USDC Spent:', usdcBalance - newUsdcBalance);

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
