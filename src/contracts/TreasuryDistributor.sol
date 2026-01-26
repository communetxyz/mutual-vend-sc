// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITreasuryDistributor} from '../interfaces/ITreasuryDistributor.sol';
import {IVendingMachine} from '../interfaces/IVendingMachine.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

/**
 * @title TreasuryDistributor
 * @notice Handles revenue sharing and dividend distribution to vote token holders
 * @dev Implements purchase-time tracking and cycle-based distribution
 */
contract TreasuryDistributor is ITreasuryDistributor, ReentrancyGuard {
  using SafeERC20 for IERC20;

  /// @notice The vending machine contract this distributor is connected to
  IVendingMachine public immutable vendingMachine;

  /// @inheritdoc ITreasuryDistributor
  uint256 public constant CYCLE_LENGTH = 30 days;
  /// @inheritdoc ITreasuryDistributor
  uint256 public currentCycle;
  /// @inheritdoc ITreasuryDistributor
  uint256 public lastCycleTimestamp;

  /// @inheritdoc ITreasuryDistributor
  address[] public currentBuyers;
  /// @inheritdoc ITreasuryDistributor
  mapping(address => bool) public isInCurrentCycle;
  /// @inheritdoc ITreasuryDistributor
  mapping(address => uint256) public eligibleBalance;
  /// @inheritdoc ITreasuryDistributor
  uint256 public totalEligible;

  /// @notice Initializes the treasury distributor with a vending machine
  /// @param _vendingMachine Address of the VendingMachine contract
  constructor(address _vendingMachine) {
    if (_vendingMachine == address(0)) revert ZeroAddress();

    vendingMachine = IVendingMachine(_vendingMachine);

    // Start first cycle
    lastCycleTimestamp = block.timestamp;
    emit NewCycleStarted(0, block.timestamp);
  }

  /// @inheritdoc ITreasuryDistributor
  function onPurchase(address buyer, uint256 amount) external {
    require(msg.sender == address(vendingMachine), 'Only vending machine can call');
    if (buyer == address(0)) return;
    if (amount == 0) return;

    // Add buyer to current cycle if not already included
    if (!isInCurrentCycle[buyer]) {
      currentBuyers.push(buyer);
      isInCurrentCycle[buyer] = true;
    }

    // Update eligible balance by adding the new amount
    uint256 oldEligible = eligibleBalance[buyer];
    uint256 newEligible = oldEligible + amount;

    // Update totals
    totalEligible = totalEligible - oldEligible + newEligible;
    eligibleBalance[buyer] = newEligible;

    emit PurchaseTracked(buyer, newEligible, totalEligible);
  }

  /// @inheritdoc ITreasuryDistributor
  function distributeMonthlyRevenue() external nonReentrant {
    if (!isCycleComplete()) revert CycleNotComplete();
    if (currentBuyers.length == 0) {
      _startNewCycle();
      return;
    }

    // Claim all revenue from VendingMachine and get tokens, amounts, and total
    (address[] memory acceptedTokens, uint256[] memory tokenBalances, uint256 totalRevenue) = _claimRevenueFromVending();

    // Distribute to all buyers
    uint256 buyerCount = currentBuyers.length;
    for (uint256 i = 0; i < buyerCount; i++) {
      address buyer = currentBuyers[i];
      uint256 buyerEligible = eligibleBalance[buyer];

      // Calculate share percentage (scaled by 1e18 for precision)
      uint256 sharePercent = (buyerEligible * 1e18) / totalEligible;

      // Distribute each token proportionally
      for (uint256 j = 0; j < acceptedTokens.length; j++) {
        if (tokenBalances[j] > 0) {
          uint256 tokenShare = (tokenBalances[j] * sharePercent) / 1e18;
          if (tokenShare > 0) {
            IERC20(acceptedTokens[j]).safeTransfer(buyer, tokenShare);
            emit DividendDistributed(buyer, acceptedTokens[j], tokenShare);
          }
        }
      }

      // Clear buyer from current cycle
      delete eligibleBalance[buyer];
      delete isInCurrentCycle[buyer];
    }

    emit CycleCompleted(currentCycle, totalRevenue, buyerCount);

    // Start new cycle
    _startNewCycle();
  }

  /// @inheritdoc ITreasuryDistributor
  function isCycleComplete() public view returns (bool) {
    return block.timestamp >= lastCycleTimestamp + CYCLE_LENGTH;
  }

  /// @inheritdoc ITreasuryDistributor
  function getCurrentBuyers() external view returns (address[] memory) {
    return currentBuyers;
  }

  /// @inheritdoc ITreasuryDistributor
  function getBuyerEligibleBalance(address buyer) external view returns (uint256) {
    return eligibleBalance[buyer];
  }

  /// @inheritdoc ITreasuryDistributor
  function getCycleInfo()
    external
    view
    returns (uint256 cycle, uint256 length, uint256 lastTimestamp, bool isComplete)
  {
    return (currentCycle, CYCLE_LENGTH, lastCycleTimestamp, isCycleComplete());
  }

  /// @inheritdoc ITreasuryDistributor
  function calculateBuyerRevShare(address buyer)
    external
    view
    returns (address[] memory tokens, uint256[] memory amounts)
  {
    // Get accepted tokens from vending machine
    tokens = vendingMachine.getAcceptedTokens();
    amounts = new uint256[](tokens.length);

    // If buyer has no eligible balance or no total eligible, return zeros
    if (eligibleBalance[buyer] == 0 || totalEligible == 0) {
      return (tokens, amounts);
    }

    // Calculate share percentage (scaled by 1e18 for precision)
    uint256 sharePercent = (eligibleBalance[buyer] * 1e18) / totalEligible;

    // Calculate buyer's share for each token
    for (uint256 i = 0; i < tokens.length; i++) {
      // Get accumulated revenue in vending machine
      uint256 vendingBalance = IERC20(tokens[i]).balanceOf(address(vendingMachine));

      // Get already claimed revenue in treasury distributor
      uint256 treasuryBalance = IERC20(tokens[i]).balanceOf(address(this));

      // Total available for distribution
      uint256 totalAvailable = vendingBalance + treasuryBalance;

      // Calculate buyer's share
      if (totalAvailable > 0) {
        amounts[i] = (totalAvailable * sharePercent) / 1e18;
      }
    }

    return (tokens, amounts);
  }

  /// @notice Claims all accumulated revenue from the vending machine
  /// @return tokens Array of token addresses withdrawn
  /// @return amounts Array of amounts withdrawn for each token
  /// @return totalRevenue Sum of all token balances withdrawn (assumes same decimals)
  function _claimRevenueFromVending()
    private
    returns (address[] memory tokens, uint256[] memory amounts, uint256 totalRevenue)
  {
    // Withdraw all revenue from vending machine
    (tokens, amounts) = vendingMachine.withdrawRevenue(address(this));

    // Calculate total revenue
    for (uint256 i = 0; i < amounts.length; i++) {
      totalRevenue += amounts[i]; // Note: assumes all tokens have same decimals for simplicity
    }
  }

  /// @notice Starts a new distribution cycle
  function _startNewCycle() private {
    // Clear current buyers array
    delete currentBuyers;

    // Reset totals
    totalEligible = 0;

    // Update cycle info
    currentCycle++;
    lastCycleTimestamp = block.timestamp;

    emit NewCycleStarted(currentCycle, block.timestamp);
  }
}
