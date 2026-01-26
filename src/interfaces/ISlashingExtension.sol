// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ISlashingExtension
 * @notice Interface for a slashing mechanism that allows VMT token holders to slash stocker security deposits
 * @dev Works alongside VendingMachine to enforce correct stocking through economic incentives
 */
interface ISlashingExtension {
  /**
   * @notice Stocker registration information
   * @param stocker Address of the registered stocker
   * @param depositAmount Amount of deposit posted
   * @param depositToken Token used for the deposit
   * @param isActive Whether the stocker is currently active
   * @param registeredAt Timestamp when the stocker registered
   */
  struct StockerInfo {
    address stocker;
    uint256 depositAmount;
    address depositToken;
    bool isActive;
    uint256 registeredAt;
  }

  /**
   * @notice Slash proposal information
   * @param id Unique proposal ID
   * @param stocker Address of the stocker being accused
   * @param reason Description of the alleged incorrect stocking
   * @param proposer Address that created the proposal
   * @param votesFor Total votes in favor of slashing
   * @param votesAgainst Total votes against slashing
   * @param snapshotBlock Block number for vote snapshot
   * @param deadline Timestamp when voting ends
   * @param executed Whether the proposal has been executed
   * @param slashed Whether the stocker was slashed (only valid if executed)
   */
  struct SlashProposal {
    uint256 id;
    address stocker;
    string reason;
    address proposer;
    uint256 votesFor;
    uint256 votesAgainst;
    uint256 snapshotBlock;
    uint256 deadline;
    bool executed;
    bool slashed;
  }

  // Custom errors
  /// @notice Thrown when stocker is not registered
  error StockerNotRegistered();
  /// @notice Thrown when stocker is already registered
  error StockerAlreadyRegistered();
  /// @notice Thrown when deposit amount is insufficient
  error InsufficientDeposit();
  /// @notice Thrown when deposit token is not accepted
  error DepositTokenNotAccepted();
  /// @notice Thrown when proposal does not exist
  error ProposalNotFound();
  /// @notice Thrown when voting period has ended
  error VotingEnded();
  /// @notice Thrown when voting period has not ended
  error VotingNotEnded();
  /// @notice Thrown when proposal is already executed
  error ProposalAlreadyExecuted();
  /// @notice Thrown when voter has already voted
  error AlreadyVoted();
  /// @notice Thrown when voter has no voting power
  error NoVotingPower();
  /// @notice Thrown when stocker has pending proposals
  error HasPendingProposals();
  /// @notice Thrown when zero address is provided
  error ZeroAddress();
  /// @notice Thrown when caller is not authorized
  error Unauthorized();
  /// @notice Thrown when withdrawal is attempted too soon after deregistration
  error WithdrawalLocked();
  /// @notice Thrown when stocker is not active
  error StockerNotActive();

  // Events
  /**
   * @notice Emitted when a stocker registers with a deposit
   * @param stocker Address of the stocker
   * @param depositToken Token used for deposit
   * @param depositAmount Amount deposited
   */
  event StockerRegistered(address indexed stocker, address indexed depositToken, uint256 depositAmount);

  /**
   * @notice Emitted when a stocker deregisters
   * @param stocker Address of the stocker
   */
  event StockerDeregistered(address indexed stocker);

  /**
   * @notice Emitted when a stocker withdraws their deposit
   * @param stocker Address of the stocker
   * @param depositToken Token withdrawn
   * @param amount Amount withdrawn
   */
  event DepositWithdrawn(address indexed stocker, address indexed depositToken, uint256 amount);

  /**
   * @notice Emitted when a slash proposal is created
   * @param proposalId ID of the proposal
   * @param stocker Address of the accused stocker
   * @param proposer Address that created the proposal
   * @param reason Reason for the slash proposal
   * @param deadline Voting deadline timestamp
   */
  event SlashProposalCreated(
    uint256 indexed proposalId,
    address indexed stocker,
    address indexed proposer,
    string reason,
    uint256 deadline
  );

  /**
   * @notice Emitted when a vote is cast on a proposal
   * @param proposalId ID of the proposal
   * @param voter Address of the voter
   * @param support Whether the vote is in favor of slashing
   * @param votes Number of votes cast
   */
  event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 votes);

  /**
   * @notice Emitted when a proposal is executed
   * @param proposalId ID of the proposal
   * @param slashed Whether the stocker was slashed
   * @param votesFor Votes in favor
   * @param votesAgainst Votes against
   */
  event ProposalExecuted(uint256 indexed proposalId, bool slashed, uint256 votesFor, uint256 votesAgainst);

  /**
   * @notice Emitted when a stocker is slashed
   * @param stocker Address of the slashed stocker
   * @param depositToken Token slashed
   * @param amount Amount slashed
   * @param recipient Recipient of slashed funds
   */
  event StockerSlashed(address indexed stocker, address indexed depositToken, uint256 amount, address recipient);

  // Functions

  /**
   * @notice Register as a stocker by posting a security deposit
   * @param depositToken ERC20 token to use for the deposit (must be accepted by vending machine)
   * @param depositAmount Amount to deposit (must meet minimum requirement)
   */
  function registerStocker(address depositToken, uint256 depositAmount) external;

  /**
   * @notice Deregister as a stocker (starts withdrawal lock period)
   * @dev Cannot deregister if there are pending slash proposals against this stocker
   */
  function deregisterStocker() external;

  /**
   * @notice Withdraw deposit after deregistration and lock period
   */
  function withdrawDeposit() external;

  /**
   * @notice Create a slash proposal against a stocker
   * @param stocker Address of the stocker to slash
   * @param reason Description of the incorrect stocking behavior
   * @return proposalId ID of the created proposal
   */
  function proposeSlash(address stocker, string calldata reason) external returns (uint256 proposalId);

  /**
   * @notice Cast a vote on a slash proposal
   * @param proposalId ID of the proposal to vote on
   * @param support True to vote for slashing, false to vote against
   */
  function castVote(uint256 proposalId, bool support) external;

  /**
   * @notice Execute a proposal after voting period ends
   * @dev Slashes the stocker if majority voted in favor
   * @param proposalId ID of the proposal to execute
   */
  function executeProposal(uint256 proposalId) external;

  /**
   * @notice Get stocker information
   * @param stocker Address of the stocker
   * @return StockerInfo structure
   */
  function getStockerInfo(address stocker) external view returns (StockerInfo memory);

  /**
   * @notice Get proposal information
   * @param proposalId ID of the proposal
   * @return SlashProposal structure
   */
  function getProposal(uint256 proposalId) external view returns (SlashProposal memory);

  /**
   * @notice Check if an address is a registered and active stocker
   * @param stocker Address to check
   * @return True if stocker is active
   */
  function isActiveStocker(address stocker) external view returns (bool);

  /**
   * @notice Get pending proposals against a stocker
   * @param stocker Address of the stocker
   * @return Array of proposal IDs
   */
  function getPendingProposals(address stocker) external view returns (uint256[] memory);

  /**
   * @notice Check if an address has voted on a proposal
   * @param proposalId ID of the proposal
   * @param voter Address of the voter
   * @return True if the address has voted
   */
  function hasVoted(uint256 proposalId, address voter) external view returns (bool);

  /**
   * @notice Get the minimum deposit required to register as a stocker
   * @return Minimum deposit amount in wei
   */
  function minDeposit() external view returns (uint256);

  /**
   * @notice Get the voting period duration
   * @return Duration in seconds
   */
  function votingPeriod() external view returns (uint256);

  /**
   * @notice Get the withdrawal lock period after deregistration
   * @return Duration in seconds
   */
  function withdrawalLockPeriod() external view returns (uint256);
}
