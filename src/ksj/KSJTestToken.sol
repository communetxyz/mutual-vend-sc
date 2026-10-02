// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
/// @notice Free test tokens, no monetary value. Never use this token for commercial sales.
contract KSJTestToken is ERC20 {
  constructor() ERC20('KSJ Test Credit - No Value', 'TEST') {}
  function faucet() external { _mint(msg.sender, 100 * 10 ** decimals()); }
}
