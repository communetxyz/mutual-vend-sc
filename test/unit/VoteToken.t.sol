// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from 'forge-std/Test.sol';
import {VoteToken} from 'contracts/VoteToken.sol';

contract VoteTokenTest is Test {
  VoteToken public token;
  address public admin = makeAddr('admin');
  address public minter = makeAddr('minter');
  address public user = makeAddr('user');

  function setUp() public {
    vm.startPrank(admin);
    token = new VoteToken('Vote', 'VT');
    token.grantRole(token.MINTER_ROLE(), minter);
    vm.stopPrank();
  }

  function test_name() public view {
    assertEq(token.name(), 'Vote');
    assertEq(token.symbol(), 'VT');
  }

  function test_mint() public {
    vm.prank(minter);
    token.mint(user, 100e18);
    assertEq(token.balanceOf(user), 100e18);
  }

  function test_mint_autoDelegates() public {
    vm.prank(minter);
    token.mint(user, 100e18);
    // Should auto-delegate to self
    assertEq(token.delegates(user), user);
    assertEq(token.getVotes(user), 100e18);
  }

  function test_mint_revertsNonMinter() public {
    vm.prank(user);
    vm.expectRevert();
    token.mint(user, 100e18);
  }

  function test_transfer() public {
    vm.prank(minter);
    token.mint(user, 100e18);

    address recipient = makeAddr('recipient');
    vm.prank(user);
    token.transfer(recipient, 50e18);

    assertEq(token.balanceOf(user), 50e18);
    assertEq(token.balanceOf(recipient), 50e18);
  }

  function test_adminCanGrantMinterRole() public {
    address newMinter = makeAddr('newMinter');
    bytes32 minterRole = token.MINTER_ROLE();
    vm.prank(admin);
    token.grantRole(minterRole, newMinter);
    assertTrue(token.hasRole(minterRole, newMinter));
  }

  function test_nonAdminCannotGrantRoles() public {
    bytes32 minterRole = token.MINTER_ROLE();
    vm.prank(user);
    vm.expectRevert();
    token.grantRole(minterRole, user);
  }
}
