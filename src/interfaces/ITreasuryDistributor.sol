// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ITreasuryDistributor
 * @notice Interface for distributing vending machine revenue to vote token holders
 * @dev Implements cycle-based proportional distribution with per-product stocker shares
 */
interface ITreasuryDistributor {
  // Events
  event PurchaseTracked(
    address indexed buyer,
    address indexed token,
    uint256 amount,
    uint256 stockerAmount,
    uint256 consumerAmount
  );

  event DistributionExecuted(
    uint256 indexed cycle,
    uint256 buyerCount,
    uint256 timestamp
  );

  event StockerPaid(
    address indexed stocker,
    address indexed token,
    uint256 amount
  );

  event ConsumerPaid(
    address indexed consumer,
    address indexed token,
    uint256 amount
  );

  event NewCycleStarted(
    uint256 indexed cycle,
    uint256 timestamp
  );

  // Errors
  error NotAuthorized();
  error CycleNotComplete();
  error InvalidAddress();
  error InvalidAmount();
  error InvalidCycleLength();
  error TransferFailed();
  error AlreadyInitialized();

  /**
   * @notice Called by VendingMachine on each purchase to track revenue and buyers
   * @param buyer Address of the purchaser
   * @param token Payment token used
   * @param amount Payment amount
   * @param stockerShareBps Product's stocker share in basis points
   * @param stockerAddress Address that receives stocker share for this product
   */
  function onPurchase(
    address buyer,
    address token,
    uint256 amount,
    uint256 stockerShareBps,
    address stockerAddress
  ) external;

  /**
   * @notice Executes distribution to stocker and consumers
   * @dev Can only be called when cycle is complete
   */
  function distribute() external;

  /**
   * @notice Checks if current cycle is complete
   * @return bool True if distribution can occur
   */
  function isCycleComplete() external view returns (bool);

  /**
   * @notice Gets the current cycle number
   * @return uint256 Current cycle
   */
  function getCurrentCycle() external view returns (uint256);

  /**
   * @notice Gets the number of buyers in current cycle
   * @return uint256 Number of unique buyers
   */
  function getCurrentBuyerCount() external view returns (uint256);

  /**
   * @notice Gets accumulated stocker revenue for a specific stocker and token
   * @param stocker Stocker address
   * @param token Token address
   * @return uint256 Stocker revenue amount
   */
  function getStockerRevenue(address stocker, address token) external view returns (uint256);

  /**
   * @notice Gets accumulated consumer revenue for a token
   * @param token Token address
   * @return uint256 Consumer revenue amount
   */
  function getConsumerRevenue(address token) external view returns (uint256);

  /**
   * @notice Gets the eligible balance for a buyer
   * @param buyer Buyer address
   * @return uint256 Eligible balance
   */
  function getEligibleBalance(address buyer) external view returns (uint256);

  /**
   * @notice Gets time until next distribution
   * @return uint256 Seconds until cycle complete
   */
  function getTimeUntilNextDistribution() external view returns (uint256);
}