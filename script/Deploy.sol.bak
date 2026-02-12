// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {VendingMachine} from 'contracts/VendingMachine.sol';
import {VoteToken} from 'contracts/VoteToken.sol';
import {Script} from 'forge-std/Script.sol';

contract Deploy is Script {
  function run() public {
    vm.startBroadcast();
    VoteToken token = new VoteToken();
    new VendingMachine(address(token));
    vm.stopBroadcast();
  }
}
