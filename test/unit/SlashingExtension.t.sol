// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from 'forge-std/Test.sol';
import {SlashingExtension, ISlashingExtension} from 'contracts/SlashingExtension.sol';
import {VendingMachine, IVendingMachine} from 'contracts/VendingMachine.sol';
import {VoteToken} from 'contracts/VoteToken.sol';
import {ERC20Mock} from './mocks/ERC20Mock.sol';
import {ERC1967Proxy} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';

contract SlashingExtensionTest is Test {
  // Contracts
  SlashingExtension internal slashing;
  SlashingExtension internal slashingImpl;
  VendingMachine internal vendingMachine;
  VoteToken internal voteToken;
  ERC20Mock internal usdc;

  // Addresses
  address internal owner = makeAddr('owner');
  address internal stocker1 = makeAddr('stocker1');
  address internal stocker2 = makeAddr('stocker2');
  address internal voter1 = makeAddr('voter1');
  address internal voter2 = makeAddr('voter2');
  address internal voter3 = makeAddr('voter3');
  address internal slashRecipient = makeAddr('slashRecipient');

  // Constants
  uint256 internal constant MIN_DEPOSIT = 100e18;
  uint256 internal constant VOTING_PERIOD = 3 days;
  uint256 internal constant WITHDRAWAL_LOCK_PERIOD = 7 days;
  uint256 internal constant INITIAL_BALANCE = 10_000e18;

  // Events
  event StockerRegistered(address indexed stocker, address indexed depositToken, uint256 depositAmount);
  event StockerDeregistered(address indexed stocker);
  event DepositWithdrawn(address indexed stocker, address indexed depositToken, uint256 amount);
  event SlashProposalCreated(
    uint256 indexed proposalId,
    address indexed stocker,
    address indexed proposer,
    string reason,
    uint256 deadline
  );
  event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 votes);
  event ProposalExecuted(uint256 indexed proposalId, bool slashed, uint256 votesFor, uint256 votesAgainst);
  event StockerSlashed(address indexed stocker, address indexed depositToken, uint256 amount, address recipient);

  function setUp() public {
    vm.startPrank(owner);

    // Deploy mock USDC
    usdc = new ERC20Mock('USD Coin', 'USDC', 6);

    // Initialize products and tokens
    address[] memory tokens = new address[](1);
    tokens[0] = address(usdc);

    IVendingMachine.Product[] memory products = new IVendingMachine.Product[](0);
    uint256[] memory stocks = new uint256[](0);
    uint256[] memory prices = new uint256[](0);

    // Deploy VendingMachine
    vendingMachine = new VendingMachine(5, 100, 'Vending Machine Token', 'VMT', tokens, products, stocks, prices);

    // Get the vote token from vending machine
    voteToken = vendingMachine.voteToken();

    // Deploy SlashingExtension implementation
    slashingImpl = new SlashingExtension();

    // Deploy proxy and initialize
    bytes memory initData = abi.encodeWithSelector(
      SlashingExtension.initialize.selector,
      address(vendingMachine),
      address(voteToken),
      MIN_DEPOSIT,
      VOTING_PERIOD,
      WITHDRAWAL_LOCK_PERIOD,
      slashRecipient
    );
    ERC1967Proxy proxy = new ERC1967Proxy(address(slashingImpl), initData);
    slashing = SlashingExtension(address(proxy));

    vm.stopPrank();

    // Setup initial balances
    usdc.mint(stocker1, INITIAL_BALANCE);
    usdc.mint(stocker2, INITIAL_BALANCE);

    // Approve slashing contract to spend deposits
    vm.prank(stocker1);
    usdc.approve(address(slashing), type(uint256).max);
    vm.prank(stocker2);
    usdc.approve(address(slashing), type(uint256).max);

    // Setup voters with voting power by having them purchase from vending machine
    _setupVoters();
  }

  function _setupVoters() internal {
    // Load a track with a product
    vm.startPrank(owner);

    IVendingMachine.Product memory product = IVendingMachine.Product({name: 'Test Product', imageURI: 'ipfs://test'});

    vendingMachine.loadTrack(0, product, 10);
    vendingMachine.setTrackPrice(0, 1000e18);

    vm.stopPrank();

    // Give voters USDC and have them purchase to get VMT
    usdc.mint(voter1, 5000e18);
    usdc.mint(voter2, 3000e18);
    usdc.mint(voter3, 2000e18);

    // Voter1 purchases - gets 1000 VMT
    vm.startPrank(voter1);
    usdc.approve(address(vendingMachine), type(uint256).max);
    vendingMachine.vendFromTrack(0, address(usdc), voter1);
    vm.stopPrank();

    // Voter2 purchases - gets 1000 VMT
    vm.startPrank(voter2);
    usdc.approve(address(vendingMachine), type(uint256).max);
    vendingMachine.vendFromTrack(0, address(usdc), voter2);
    vm.stopPrank();

    // Voter3 purchases - gets 1000 VMT
    vm.startPrank(voter3);
    usdc.approve(address(vendingMachine), type(uint256).max);
    vendingMachine.vendFromTrack(0, address(usdc), voter3);
    vm.stopPrank();
  }

  // ==================== Constructor/Initialize Tests ====================

  function test_InitializeSetsParameters() public view {
    assertEq(address(slashing.vendingMachine()), address(vendingMachine));
    assertEq(address(slashing.voteToken()), address(voteToken));
    assertEq(slashing.minDeposit(), MIN_DEPOSIT);
    assertEq(slashing.votingPeriod(), VOTING_PERIOD);
    assertEq(slashing.withdrawalLockPeriod(), WITHDRAWAL_LOCK_PERIOD);
    assertEq(slashing.slashRecipient(), slashRecipient);
  }

  function test_InitializeRevertsOnZeroAddresses() public {
    vm.startPrank(owner);

    SlashingExtension newImpl = new SlashingExtension();

    // Zero vending machine
    bytes memory initData = abi.encodeWithSelector(
      SlashingExtension.initialize.selector,
      address(0),
      address(voteToken),
      MIN_DEPOSIT,
      VOTING_PERIOD,
      WITHDRAWAL_LOCK_PERIOD,
      slashRecipient
    );
    vm.expectRevert(ISlashingExtension.ZeroAddress.selector);
    new ERC1967Proxy(address(newImpl), initData);

    // Zero vote token
    initData = abi.encodeWithSelector(
      SlashingExtension.initialize.selector,
      address(vendingMachine),
      address(0),
      MIN_DEPOSIT,
      VOTING_PERIOD,
      WITHDRAWAL_LOCK_PERIOD,
      slashRecipient
    );
    vm.expectRevert(ISlashingExtension.ZeroAddress.selector);
    new ERC1967Proxy(address(newImpl), initData);

    // Zero slash recipient
    initData = abi.encodeWithSelector(
      SlashingExtension.initialize.selector,
      address(vendingMachine),
      address(voteToken),
      MIN_DEPOSIT,
      VOTING_PERIOD,
      WITHDRAWAL_LOCK_PERIOD,
      address(0)
    );
    vm.expectRevert(ISlashingExtension.ZeroAddress.selector);
    new ERC1967Proxy(address(newImpl), initData);

    vm.stopPrank();
  }

  function test_CannotReinitialize() public {
    vm.prank(owner);
    vm.expectRevert();
    slashing.initialize(
      address(vendingMachine),
      address(voteToken),
      MIN_DEPOSIT,
      VOTING_PERIOD,
      WITHDRAWAL_LOCK_PERIOD,
      slashRecipient
    );
  }

  function test_ImplementationCannotBeInitialized() public {
    vm.prank(owner);
    vm.expectRevert();
    slashingImpl.initialize(
      address(vendingMachine),
      address(voteToken),
      MIN_DEPOSIT,
      VOTING_PERIOD,
      WITHDRAWAL_LOCK_PERIOD,
      slashRecipient
    );
  }

  // ==================== Registration Tests ====================

  function test_RegisterStockerSuccess() public {
    vm.prank(stocker1);

    vm.expectEmit(true, true, true, true);
    emit StockerRegistered(stocker1, address(usdc), MIN_DEPOSIT);

    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    ISlashingExtension.StockerInfo memory info = slashing.getStockerInfo(stocker1);
    assertEq(info.stocker, stocker1);
    assertEq(info.depositAmount, MIN_DEPOSIT);
    assertEq(info.depositToken, address(usdc));
    assertTrue(info.isActive);
    assertEq(info.registeredAt, block.timestamp);
  }

  function test_RegisterStockerWithLargerDeposit() public {
    uint256 largerDeposit = MIN_DEPOSIT * 2;

    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), largerDeposit);

    ISlashingExtension.StockerInfo memory info = slashing.getStockerInfo(stocker1);
    assertEq(info.depositAmount, largerDeposit);
  }

  function test_RegisterStockerRevertsIfAlreadyRegistered() public {
    vm.startPrank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    vm.expectRevert(ISlashingExtension.StockerAlreadyRegistered.selector);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);
    vm.stopPrank();
  }

  function test_RegisterStockerRevertsIfInsufficientDeposit() public {
    vm.prank(stocker1);

    vm.expectRevert(ISlashingExtension.InsufficientDeposit.selector);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT - 1);
  }

  function test_RegisterStockerRevertsIfTokenNotAccepted() public {
    ERC20Mock notAccepted = new ERC20Mock('Not Accepted', 'NA', 18);
    notAccepted.mint(stocker1, MIN_DEPOSIT);

    vm.startPrank(stocker1);
    notAccepted.approve(address(slashing), type(uint256).max);

    vm.expectRevert(ISlashingExtension.DepositTokenNotAccepted.selector);
    slashing.registerStocker(address(notAccepted), MIN_DEPOSIT);
    vm.stopPrank();
  }

  // ==================== Deregistration Tests ====================

  function test_DeregisterStockerSuccess() public {
    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    vm.prank(stocker1);

    vm.expectEmit(true, true, true, true);
    emit StockerDeregistered(stocker1);

    slashing.deregisterStocker();

    ISlashingExtension.StockerInfo memory info = slashing.getStockerInfo(stocker1);
    assertFalse(info.isActive);
    assertEq(slashing.getDeregistrationTime(stocker1), block.timestamp);
  }

  function test_DeregisterStockerRevertsIfNotRegistered() public {
    vm.prank(stocker1);

    vm.expectRevert(ISlashingExtension.StockerNotRegistered.selector);
    slashing.deregisterStocker();
  }

  function test_DeregisterStockerRevertsIfPendingProposals() public {
    // Register stocker
    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    // Create a slash proposal against stocker1
    vm.prank(voter1);
    slashing.proposeSlash(stocker1, 'Stocked wrong items');

    // Try to deregister - should fail
    vm.prank(stocker1);
    vm.expectRevert(ISlashingExtension.HasPendingProposals.selector);
    slashing.deregisterStocker();
  }

  // ==================== Withdrawal Tests ====================

  function test_WithdrawDepositSuccess() public {
    // Register
    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    // Deregister
    vm.prank(stocker1);
    slashing.deregisterStocker();

    // Wait for lock period
    vm.warp(block.timestamp + WITHDRAWAL_LOCK_PERIOD + 1);

    uint256 balanceBefore = usdc.balanceOf(stocker1);

    vm.prank(stocker1);

    vm.expectEmit(true, true, true, true);
    emit DepositWithdrawn(stocker1, address(usdc), MIN_DEPOSIT);

    slashing.withdrawDeposit();

    uint256 balanceAfter = usdc.balanceOf(stocker1);
    assertEq(balanceAfter - balanceBefore, MIN_DEPOSIT);

    ISlashingExtension.StockerInfo memory info = slashing.getStockerInfo(stocker1);
    assertEq(info.depositAmount, 0);
    assertEq(info.depositToken, address(0));
  }

  function test_WithdrawDepositRevertsIfNotRegistered() public {
    vm.prank(stocker1);

    vm.expectRevert(ISlashingExtension.StockerNotRegistered.selector);
    slashing.withdrawDeposit();
  }

  function test_WithdrawDepositRevertsIfStillActive() public {
    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    vm.prank(stocker1);
    vm.expectRevert(ISlashingExtension.StockerNotActive.selector);
    slashing.withdrawDeposit();
  }

  function test_WithdrawDepositRevertsIfLockNotExpired() public {
    // Register
    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    // Deregister
    vm.prank(stocker1);
    slashing.deregisterStocker();

    // Try to withdraw before lock period
    vm.prank(stocker1);
    vm.expectRevert(ISlashingExtension.WithdrawalLocked.selector);
    slashing.withdrawDeposit();
  }

  // ==================== Proposal Tests ====================

  function test_ProposeSlashSuccess() public {
    // Register stocker
    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    string memory reason = 'Stocked expired products';

    vm.prank(voter1);

    vm.expectEmit(true, true, true, false);
    emit SlashProposalCreated(1, stocker1, voter1, reason, block.timestamp + VOTING_PERIOD);

    uint256 proposalId = slashing.proposeSlash(stocker1, reason);

    assertEq(proposalId, 1);

    ISlashingExtension.SlashProposal memory proposal = slashing.getProposal(proposalId);
    assertEq(proposal.id, 1);
    assertEq(proposal.stocker, stocker1);
    assertEq(proposal.reason, reason);
    assertEq(proposal.proposer, voter1);
    assertEq(proposal.votesFor, 0);
    assertEq(proposal.votesAgainst, 0);
    assertEq(proposal.snapshotBlock, block.number);
    assertEq(proposal.deadline, block.timestamp + VOTING_PERIOD);
    assertFalse(proposal.executed);
    assertFalse(proposal.slashed);
  }

  function test_ProposeSlashRevertsIfStockerNotRegistered() public {
    vm.prank(voter1);

    vm.expectRevert(ISlashingExtension.StockerNotRegistered.selector);
    slashing.proposeSlash(stocker1, 'Invalid');
  }

  function test_ProposeSlashRevertsIfNoVotingPower() public {
    // Register stocker
    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    address noVotes = makeAddr('noVotes');

    vm.prank(noVotes);
    vm.expectRevert(ISlashingExtension.NoVotingPower.selector);
    slashing.proposeSlash(stocker1, 'Invalid');
  }

  function test_MultiplePendingProposals() public {
    // Register stocker
    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    // Create multiple proposals
    vm.prank(voter1);
    slashing.proposeSlash(stocker1, 'Reason 1');

    vm.prank(voter2);
    slashing.proposeSlash(stocker1, 'Reason 2');

    uint256[] memory pending = slashing.getPendingProposals(stocker1);
    assertEq(pending.length, 2);
    assertEq(pending[0], 1);
    assertEq(pending[1], 2);
  }

  // ==================== Voting Tests ====================

  function test_CastVoteForSuccess() public {
    // Register stocker
    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    // Create proposal
    vm.prank(voter1);
    uint256 proposalId = slashing.proposeSlash(stocker1, 'Bad stocking');

    // Move forward a block for getPastVotes to work
    vm.roll(block.number + 1);

    uint256 expectedVotes = voteToken.getPastVotes(voter2, block.number - 1);

    vm.prank(voter2);

    vm.expectEmit(true, true, true, true);
    emit VoteCast(proposalId, voter2, true, expectedVotes);

    slashing.castVote(proposalId, true);

    ISlashingExtension.SlashProposal memory proposal = slashing.getProposal(proposalId);
    assertEq(proposal.votesFor, expectedVotes);
    assertEq(proposal.votesAgainst, 0);
    assertTrue(slashing.hasVoted(proposalId, voter2));
  }

  function test_CastVoteAgainstSuccess() public {
    // Register stocker
    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    // Create proposal
    vm.prank(voter1);
    uint256 proposalId = slashing.proposeSlash(stocker1, 'Bad stocking');

    vm.roll(block.number + 1);

    uint256 expectedVotes = voteToken.getPastVotes(voter2, block.number - 1);

    vm.prank(voter2);
    slashing.castVote(proposalId, false);

    ISlashingExtension.SlashProposal memory proposal = slashing.getProposal(proposalId);
    assertEq(proposal.votesFor, 0);
    assertEq(proposal.votesAgainst, expectedVotes);
  }

  function test_CastVoteRevertsIfProposalNotFound() public {
    vm.prank(voter1);

    vm.expectRevert(ISlashingExtension.ProposalNotFound.selector);
    slashing.castVote(999, true);
  }

  function test_CastVoteRevertsIfVotingEnded() public {
    // Register stocker
    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    // Create proposal
    vm.prank(voter1);
    uint256 proposalId = slashing.proposeSlash(stocker1, 'Bad stocking');

    // Skip past voting period
    vm.warp(block.timestamp + VOTING_PERIOD + 1);

    vm.prank(voter2);
    vm.expectRevert(ISlashingExtension.VotingEnded.selector);
    slashing.castVote(proposalId, true);
  }

  function test_CastVoteRevertsIfAlreadyVoted() public {
    // Register stocker
    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    // Create proposal
    vm.prank(voter1);
    uint256 proposalId = slashing.proposeSlash(stocker1, 'Bad stocking');

    vm.roll(block.number + 1);

    vm.startPrank(voter2);
    slashing.castVote(proposalId, true);

    vm.expectRevert(ISlashingExtension.AlreadyVoted.selector);
    slashing.castVote(proposalId, false);
    vm.stopPrank();
  }

  function test_CastVoteRevertsIfNoVotingPower() public {
    // Register stocker
    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    // Create proposal
    vm.prank(voter1);
    uint256 proposalId = slashing.proposeSlash(stocker1, 'Bad stocking');

    vm.roll(block.number + 1);

    address noVotes = makeAddr('noVotes');

    vm.prank(noVotes);
    vm.expectRevert(ISlashingExtension.NoVotingPower.selector);
    slashing.castVote(proposalId, true);
  }

  // ==================== Execution Tests ====================

  function test_ExecuteProposalSlashSuccess() public {
    // Register stocker
    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    // Create proposal
    vm.prank(voter1);
    uint256 proposalId = slashing.proposeSlash(stocker1, 'Bad stocking');

    vm.roll(block.number + 1);

    // Vote for slashing (majority)
    vm.prank(voter1);
    slashing.castVote(proposalId, true);
    vm.prank(voter2);
    slashing.castVote(proposalId, true);

    // Vote against (minority)
    vm.prank(voter3);
    slashing.castVote(proposalId, false);

    // Skip to end of voting period
    vm.warp(block.timestamp + VOTING_PERIOD + 1);

    uint256 recipientBalanceBefore = usdc.balanceOf(slashRecipient);

    ISlashingExtension.SlashProposal memory proposalBefore = slashing.getProposal(proposalId);

    vm.expectEmit(true, true, true, true);
    emit StockerSlashed(stocker1, address(usdc), MIN_DEPOSIT, slashRecipient);

    vm.expectEmit(true, true, true, true);
    emit ProposalExecuted(proposalId, true, proposalBefore.votesFor, proposalBefore.votesAgainst);

    slashing.executeProposal(proposalId);

    // Verify slashing occurred
    ISlashingExtension.SlashProposal memory proposal = slashing.getProposal(proposalId);
    assertTrue(proposal.executed);
    assertTrue(proposal.slashed);

    // Verify deposit transferred to recipient
    uint256 recipientBalanceAfter = usdc.balanceOf(slashRecipient);
    assertEq(recipientBalanceAfter - recipientBalanceBefore, MIN_DEPOSIT);

    // Verify stocker deactivated and deposit cleared
    ISlashingExtension.StockerInfo memory info = slashing.getStockerInfo(stocker1);
    assertFalse(info.isActive);
    assertEq(info.depositAmount, 0);
  }

  function test_ExecuteProposalNoSlashWhenVotesAgainst() public {
    // Register stocker
    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    // Create proposal
    vm.prank(voter1);
    uint256 proposalId = slashing.proposeSlash(stocker1, 'Bad stocking');

    vm.roll(block.number + 1);

    // Vote against slashing (majority)
    vm.prank(voter1);
    slashing.castVote(proposalId, false);
    vm.prank(voter2);
    slashing.castVote(proposalId, false);

    // Vote for (minority)
    vm.prank(voter3);
    slashing.castVote(proposalId, true);

    // Skip to end of voting period
    vm.warp(block.timestamp + VOTING_PERIOD + 1);

    slashing.executeProposal(proposalId);

    // Verify no slashing occurred
    ISlashingExtension.SlashProposal memory proposal = slashing.getProposal(proposalId);
    assertTrue(proposal.executed);
    assertFalse(proposal.slashed);

    // Verify stocker still active with deposit
    ISlashingExtension.StockerInfo memory info = slashing.getStockerInfo(stocker1);
    assertTrue(info.isActive);
    assertEq(info.depositAmount, MIN_DEPOSIT);
  }

  function test_ExecuteProposalNoSlashWhenTie() public {
    // Register stocker
    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    // Create proposal
    vm.prank(voter1);
    uint256 proposalId = slashing.proposeSlash(stocker1, 'Bad stocking');

    vm.roll(block.number + 1);

    // Equal votes - since all voters have same voting power
    vm.prank(voter1);
    slashing.castVote(proposalId, true);
    vm.prank(voter2);
    slashing.castVote(proposalId, false);
    // voter3 abstains

    // Skip to end of voting period
    vm.warp(block.timestamp + VOTING_PERIOD + 1);

    slashing.executeProposal(proposalId);

    // On a tie (votesFor == votesAgainst), votesFor > votesAgainst is false, so no slash
    ISlashingExtension.SlashProposal memory proposal = slashing.getProposal(proposalId);
    assertTrue(proposal.executed);
    assertFalse(proposal.slashed);
  }

  function test_ExecuteProposalRevertsIfNotFound() public {
    vm.expectRevert(ISlashingExtension.ProposalNotFound.selector);
    slashing.executeProposal(999);
  }

  function test_ExecuteProposalRevertsIfVotingNotEnded() public {
    // Register stocker
    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    // Create proposal
    vm.prank(voter1);
    uint256 proposalId = slashing.proposeSlash(stocker1, 'Bad stocking');

    vm.expectRevert(ISlashingExtension.VotingNotEnded.selector);
    slashing.executeProposal(proposalId);
  }

  function test_ExecuteProposalRevertsIfAlreadyExecuted() public {
    // Register stocker
    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    // Create proposal
    vm.prank(voter1);
    uint256 proposalId = slashing.proposeSlash(stocker1, 'Bad stocking');

    vm.roll(block.number + 1);

    vm.prank(voter1);
    slashing.castVote(proposalId, true);

    vm.warp(block.timestamp + VOTING_PERIOD + 1);

    slashing.executeProposal(proposalId);

    vm.expectRevert(ISlashingExtension.ProposalAlreadyExecuted.selector);
    slashing.executeProposal(proposalId);
  }

  // ==================== Deregistration After Proposal Execution ====================

  function test_CanDeregisterAfterProposalExecuted() public {
    // Register stocker
    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    // Create proposal
    vm.prank(voter1);
    uint256 proposalId = slashing.proposeSlash(stocker1, 'Bad stocking');

    vm.roll(block.number + 1);

    // Vote against slashing
    vm.prank(voter1);
    slashing.castVote(proposalId, false);
    vm.prank(voter2);
    slashing.castVote(proposalId, false);

    // Execute proposal (no slash)
    vm.warp(block.timestamp + VOTING_PERIOD + 1);
    slashing.executeProposal(proposalId);

    // Now stocker can deregister
    vm.prank(stocker1);
    slashing.deregisterStocker();

    assertFalse(slashing.isActiveStocker(stocker1));
  }

  // ==================== Re-registration Tests ====================

  function test_CanReregisterAfterWithdrawal() public {
    // Register
    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    // Deregister
    vm.prank(stocker1);
    slashing.deregisterStocker();

    // Wait and withdraw
    vm.warp(block.timestamp + WITHDRAWAL_LOCK_PERIOD + 1);
    vm.prank(stocker1);
    slashing.withdrawDeposit();

    // Re-register
    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    assertTrue(slashing.isActiveStocker(stocker1));
  }

  // ==================== View Function Tests ====================

  function test_IsActiveStocker() public {
    assertFalse(slashing.isActiveStocker(stocker1));

    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    assertTrue(slashing.isActiveStocker(stocker1));
  }

  function test_ProposalCount() public {
    assertEq(slashing.proposalCount(), 0);

    vm.prank(stocker1);
    slashing.registerStocker(address(usdc), MIN_DEPOSIT);

    vm.prank(voter1);
    slashing.proposeSlash(stocker1, 'Reason 1');

    assertEq(slashing.proposalCount(), 1);

    vm.prank(voter2);
    slashing.proposeSlash(stocker1, 'Reason 2');

    assertEq(slashing.proposalCount(), 2);
  }

  // ==================== Set Slash Recipient Tests ====================

  function test_SetSlashRecipientSuccess() public {
    address newRecipient = makeAddr('newRecipient');

    vm.prank(owner);
    slashing.setSlashRecipient(newRecipient);

    assertEq(slashing.slashRecipient(), newRecipient);
  }

  function test_SetSlashRecipientRevertsIfZeroAddress() public {
    vm.prank(owner);

    vm.expectRevert(ISlashingExtension.ZeroAddress.selector);
    slashing.setSlashRecipient(address(0));
  }

  function test_SetSlashRecipientRevertsIfUnauthorized() public {
    address unauthorized = makeAddr('unauthorized');

    vm.prank(unauthorized);
    vm.expectRevert();
    slashing.setSlashRecipient(unauthorized);
  }

  // ==================== Upgrade Tests ====================

  function test_UpgradeSuccess() public {
    // Deploy new implementation
    vm.startPrank(owner);
    SlashingExtension newImpl = new SlashingExtension();

    // Upgrade to new implementation
    slashing.upgradeToAndCall(address(newImpl), '');
    vm.stopPrank();

    // Verify state is preserved
    assertEq(address(slashing.vendingMachine()), address(vendingMachine));
    assertEq(slashing.minDeposit(), MIN_DEPOSIT);
  }

  function test_UpgradeRevertsIfUnauthorized() public {
    address unauthorized = makeAddr('unauthorized');

    vm.startPrank(owner);
    SlashingExtension newImpl = new SlashingExtension();
    vm.stopPrank();

    vm.prank(unauthorized);
    vm.expectRevert();
    slashing.upgradeToAndCall(address(newImpl), '');
  }
}
