// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

interface IVoteToken is IERC20, IVotes {
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function grantRole(bytes32 role, address account) external;
    function MINTER_ROLE() external view returns (bytes32);
}
