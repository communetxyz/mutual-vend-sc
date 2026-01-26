// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ITreasuryDistributor
 * @notice Interface for treasury distribution to vote token holders
 * @dev Handles revenue sharing through cycle-based dividend distributions
 */
interface ITreasuryDistributor {
  /// @notice Emitted when a purchase is tracked for revenue sharing
  /// @param buyer Address that made the purchase
  /// @param eligibleAmount Buyer's new eligible balance
  /// @param totalEligible Total eligible balance across all buyers
  event PurchaseTracked(address indexed buyer, uint256 eligibleAmount, uint256 totalEligible);

  /// @notice Emitted when a distribution cycle is completed
  /// @param cycle Cycle number that was completed
  /// @param totalRevenue Total revenue distributed
  /// @param buyerCount Number of buyers who received dividends
  event CycleCompleted(uint256 indexed cycle, uint256 totalRevenue, uint256 buyerCount);

  /// @notice Emitted when a dividend is distributed to a recipient
  /// @param recipient Address receiving the dividend
  /// @param token Token address being distributed
  /// @param amount Amount distributed
  event DividendDistributed(address indexed recipient, address indexed token, uint256 amount);

  /// @notice Emitted when a new distribution cycle starts
  /// @param cycle New cycle number
  /// @param timestamp Timestamp when the cycle started
  event NewCycleStarted(uint256 indexed cycle, uint256 timestamp);

  /// @notice Thrown when a zero address is provided where not allowed
  error ZeroAddress();

  /// @notice Thrown when attempting to distribute before cycle is complete
  error CycleNotComplete();

  // State variable getters
  /// @notice Returns the cycle length in seconds (30 days)
  /// @return Cycle length constant
  function CYCLE_LENGTH() external view returns (uint256);

  /// @notice Returns the current cycle number
  /// @return Current cycle count
  function currentCycle() external view returns (uint256);

  /// @notice Returns the timestamp when the last cycle started
  /// @return Last cycle start timestamp
  function lastCycleTimestamp() external view returns (uint256);

  /// @notice Returns the address at the given index in the current buyers list
  /// @param index Index in the currentBuyers array
  /// @return Buyer address at the given index
  function currentBuyers(uint256 index) external view returns (address);

  /// @notice Returns whether the address is in the current cycle
  /// @param buyer Address to check
  /// @return True if the buyer is in the current cycle
  function isInCurrentCycle(address buyer) external view returns (bool);

  /// @notice Returns the eligible balance for a buyer
  /// @param buyer Address to check
  /// @return The eligible balance amount
  function eligibleBalance(address buyer) external view returns (uint256);

  /// @notice Returns the total eligible balance across all buyers
  /// @return Total eligible balance
  function totalEligible() external view returns (uint256);

  /**
   * @notice Called by VendingMachine when a purchase is made
   * @param buyer Address that made the purchase
   * @param amount Amount of vote tokens minted
   */
  function onPurchase(address buyer, uint256 amount) external;

  /**
   * @notice Distribute monthly revenue to vote token holders
   * @dev Can be called by anyone when cycle is complete
   */
  function distributeMonthlyRevenue() external;

  /**
   * @notice Check if current cycle is complete
   * @return True if cycle duration has passed
   */
  function isCycleComplete() external view returns (bool);

  /**
   * @notice Get list of current buyers in cycle
   * @return Array of buyer addresses
   */
  function getCurrentBuyers() external view returns (address[] memory);

  /**
   * @notice Get buyer's eligible balance for current cycle
   * @param buyer Address to check
   * @return Eligible balance amount
   */
  function getBuyerEligibleBalance(address buyer) external view returns (uint256);

  /**
   * @notice Get cycle information
   * @return cycle Current cycle number
   * @return length Cycle length in seconds
   * @return lastTimestamp Last cycle start timestamp
   * @return isComplete Whether current cycle is complete
   */
  function getCycleInfo() external view returns (uint256 cycle, uint256 length, uint256 lastTimestamp, bool isComplete);

  /**
   * @notice Calculate buyer's current revenue share eligibility including accumulated revenue
   * @param buyer Address to calculate eligibility for
   * @return tokens Array of token addresses
   * @return amounts Array of amounts the buyer would receive if distribution happened now
   */
  function calculateBuyerRevShare(address buyer)
    external
    view
    returns (address[] memory tokens, uint256[] memory amounts);
}
