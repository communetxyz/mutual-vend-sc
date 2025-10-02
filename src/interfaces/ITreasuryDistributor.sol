// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ITreasuryDistributor
 * @notice Interface for distributing vending machine revenue to vote token holders
 * @dev Implements cycle-based proportional distribution with configurable distribution percentage
 * @dev Revenue not distributed is retained for owner withdrawal
 */
interface ITreasuryDistributor {
  // Events
  /**
   * @notice Emitted when a purchase is tracked for revenue distribution
   * @param buyer Address of the purchaser who will receive distributions
   * @param token Payment token used for the purchase
   * @param amount Total payment amount
   * @param distributedAmount Amount added to distribution pool
   * @param retainedAmount Amount retained for owner withdrawal
   */
  event PurchaseTracked(
    address indexed buyer,
    address indexed token,
    uint256 amount,
    uint256 distributedAmount,
    uint256 retainedAmount
  );

  /**
   * @notice Emitted when a distribution cycle is completed
   * @param cycle The cycle number that was completed
   * @param buyerCount Number of unique buyers in the cycle
   * @param timestamp When the distribution occurred
   */
  event DistributionExecuted(
    uint256 indexed cycle,
    uint256 buyerCount,
    uint256 timestamp
  );

  /**
   * @notice Emitted when a consumer receives their distribution
   * @param consumer Address receiving the distribution
   * @param token Token being distributed
   * @param amount Amount distributed to the consumer
   */
  event ConsumerPaid(
    address indexed consumer,
    address indexed token,
    uint256 amount
  );

  /**
   * @notice Emitted when a new distribution cycle begins
   * @param cycle The new cycle number
   * @param timestamp When the cycle started
   */
  event NewCycleStarted(
    uint256 indexed cycle,
    uint256 timestamp
  );

  /**
   * @notice Emitted when the distribution percentage is updated
   * @param oldPercentage Previous percentage (in basis points)
   * @param newPercentage New percentage (in basis points)
   */
  event DistributionPercentageUpdated(
    uint256 oldPercentage,
    uint256 newPercentage
  );

  /**
   * @notice Emitted when the owner withdraws retained revenue
   * @param token Token withdrawn
   * @param amount Amount withdrawn
   * @param recipient Address receiving the funds
   */
  event RetainedRevenueWithdrawn(
    address indexed token,
    uint256 amount,
    address indexed recipient
  );

  // Errors
  /**
   * @notice Thrown when the caller is not authorized to perform the action
   */
  error NotAuthorized();
  
  /**
   * @notice Thrown when trying to distribute before the cycle is complete
   */
  error CycleNotComplete();
  
  /**
   * @notice Thrown when an invalid address (e.g., zero address) is provided
   */
  error InvalidAddress();
  
  /**
   * @notice Thrown when an invalid amount is provided
   */
  error InvalidAmount();
  
  /**
   * @notice Thrown when an invalid cycle length is provided
   */
  error InvalidCycleLength();
  
  /**
   * @notice Thrown when an invalid percentage (> 100%) is provided
   */
  error InvalidPercentage();
  
  /**
   * @notice Thrown when a token transfer fails
   */
  error TransferFailed();
  
  /**
   * @notice Thrown when trying to initialize an already initialized contract
   */
  error AlreadyInitialized();
  
  /**
   * @notice Thrown when trying to withdraw with no revenue available
   */
  error NoRevenueToWithdraw();
  
  /**
   * @notice Thrown when the contract has insufficient balance for a withdrawal
   */
  error InsufficientBalance();

  /**
   * @notice Initializes the treasury distributor contract
   * @param _voteToken Address of the vote token used for calculating distributions
   * @param _vendingMachine Address of the vending machine contract
   * @param _cycleLength Duration of each distribution cycle in seconds
   * @param _distributionPercentageBps Percentage of revenue to distribute (in basis points, e.g., 8000 = 80%)
   */
  function initialize(
    address _voteToken,
    address _vendingMachine,
    uint256 _cycleLength,
    uint256 _distributionPercentageBps
  ) external;

  /**
   * @notice Called by VendingMachine on each purchase to track revenue and buyers
   * @dev Only the vending machine can call this function
   * @param buyer Address of the purchaser who will receive vote tokens
   * @param token Payment token used for the purchase
   * @param amount Total payment amount before distribution split
   */
  function onPurchase(
    address buyer,
    address token,
    uint256 amount
  ) external;

  /**
   * @notice Executes distribution to vote token holders for the completed cycle
   * @dev Can only be called after the current cycle is complete
   * @dev Distributes accumulated revenue proportionally based on vote token holdings
   */
  function distribute() external;

  /**
   * @notice Updates the percentage of revenue that gets distributed vs retained
   * @dev Only callable by contract owner
   * @param newPercentageBps New distribution percentage in basis points (0-10000)
   */
  function setDistributionPercentage(uint256 newPercentageBps) external;

  /**
   * @notice Withdraws retained (non-distributed) revenue
   * @dev Only callable by contract owner
   * @param token Address of the token to withdraw
   * @param recipient Address to receive the withdrawn funds
   */
  function withdrawRetainedRevenue(address token, address recipient) external;

  /**
   * @notice Checks if the current distribution cycle is complete
   * @return bool True if enough time has passed and distribution can occur
   */
  function isCycleComplete() external view returns (bool);

  /**
   * @notice Gets the current cycle number
   * @return uint256 Current cycle number (starts at 1)
   */
  function getCurrentCycle() external view returns (uint256);

  /**
   * @notice Gets the number of unique buyers in the current cycle
   * @return uint256 Number of unique buyers who have made purchases
   */
  function getCurrentBuyerCount() external view returns (uint256);

  /**
   * @notice Gets the current distribution percentage
   * @return uint256 Distribution percentage in basis points
   */
  function getDistributionPercentage() external view returns (uint256);

  /**
   * @notice Gets accumulated revenue for distribution for a specific token
   * @param token Token address to query
   * @return uint256 Amount of revenue accumulated for distribution
   */
  function getDistributableRevenue(address token) external view returns (uint256);

  /**
   * @notice Gets retained revenue available for withdrawal for a specific token
   * @param token Token address to query
   * @return uint256 Amount of retained revenue available for withdrawal
   */
  function getRetainedRevenue(address token) external view returns (uint256);

  /**
   * @notice Gets the eligible vote token balance for a buyer in the current cycle
   * @param buyer Buyer address to query
   * @return uint256 Eligible balance that will be used for distribution calculations
   */
  function getEligibleBalance(address buyer) external view returns (uint256);

  /**
   * @notice Gets time remaining until the next distribution can occur
   * @return uint256 Seconds until cycle completes (0 if already complete)
   */
  function getTimeUntilNextDistribution() external view returns (uint256);

  /**
   * @notice Gets the contract owner address
   * @return address Owner address who can withdraw retained revenue
   */
  function owner() external view returns (address);
}