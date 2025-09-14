// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVotes} from '@openzeppelin/contracts/governance/utils/IVotes.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

/**
 * @title IVoteToken
 * @notice Interface for the vending machine's participation token with voting capabilities
 * @dev Extends ERC20 with voting power delegation and minting capabilities
 */
interface IVoteToken is IERC20, IVotes {
  /**
   * @notice Mints new tokens to a specified address
   * @dev Only callable by addresses with MINTER_ROLE
   * @param to The address to receive the minted tokens
   * @param amount The amount of tokens to mint
   */
  function mint(address to, uint256 amount) external;

  /**
   * @notice Grants a role to an account
   * @dev Can only be called by role admin
   * @param role The role to grant
   * @param account The account to receive the role
   */
  function grantRole(bytes32 role, address account) external;

  /**
   * @notice Returns the minter role identifier
   * @return The bytes32 identifier for the minter role
   */
  function MINTER_ROLE() external view returns (bytes32);
}
