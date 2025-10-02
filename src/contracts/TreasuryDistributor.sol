// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITreasuryDistributor} from '../interfaces/ITreasuryDistributor.sol';
import {IVoteToken} from '../interfaces/IVoteToken.sol';
import {IVendingMachine} from '../interfaces/IVendingMachine.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {Initializable} from '@openzeppelin/contracts/proxy/utils/Initializable.sol';

/**
 * @title TreasuryDistributor
 * @notice Distributes vending machine revenue to vote token holders
 * @dev Uses cycle-based distribution with proportional allocation
 */
contract TreasuryDistributor is ITreasuryDistributor, ReentrancyGuard, Initializable {
  using SafeERC20 for IERC20;

  // State variables
  IVoteToken public voteToken;
  IVendingMachine public vendingMachine;
  uint256 public cycleLength;
  uint256 public distributionPercentageBps; // Percentage in basis points (e.g., 8000 = 80%)

  address[] public currentBuyers;
  
  mapping(address => uint256) public eligibleBalance;
  mapping(address => uint256) public lastIncludedBalance;
  mapping(address => bool) public isInCurrentCycle;
  mapping(address => uint256) public distributableRevenue; // token => amount for distribution
  mapping(address => uint256) public retainedRevenue; // token => amount retained for owner

  uint256 public totalEligible;
  uint256 public currentCycle;
  uint256 public lastCycleTimestamp;

  uint256 private constant MAX_BPS = 10000; // 100% in basis points
  
  address private _owner;

  /**
   * @notice Initializes the treasury distributor
   * @param _voteToken The vote token used for calculating distributions
   * @param _vendingMachine The vending machine contract
   * @param _cycleLength The distribution cycle length in seconds
   * @param _distributionPercentageBps Percentage of revenue to distribute (in basis points)
   */
  function initialize(
    address _voteToken,
    address _vendingMachine,
    uint256 _cycleLength,
    uint256 _distributionPercentageBps
  ) external initializer {
    if (_voteToken == address(0)) revert InvalidAddress();
    if (_vendingMachine == address(0)) revert InvalidAddress();
    if (_cycleLength == 0) revert InvalidCycleLength();
    if (_distributionPercentageBps > MAX_BPS) revert InvalidPercentage();

    _owner = msg.sender;
    
    voteToken = IVoteToken(_voteToken);
    vendingMachine = IVendingMachine(_vendingMachine);
    cycleLength = _cycleLength;
    distributionPercentageBps = _distributionPercentageBps;
    
    lastCycleTimestamp = block.timestamp;
    currentCycle = 1;
  }

  /**
   * @notice Called by VendingMachine on each purchase to track revenue and buyers
   * @dev Assumes buyer and token validation done upstream in VendingMachine
   * @dev Assumes vote tokens already minted to buyer before this call
   */
  function onPurchase(
    address buyer,
    address token,
    uint256 amount
  ) external override {
    // Only accept calls from the vending machine
    if (msg.sender != address(vendingMachine)) revert NotAuthorized();
    
    // Add buyer to current cycle if not already added
    bool isNewBuyer = !isInCurrentCycle[buyer];
    if (isNewBuyer) {
      currentBuyers.push(buyer);
      isInCurrentCycle[buyer] = true;
    }

    // Get buyer's current vote token balance (already includes new tokens from this purchase)
    uint256 currentBalance = voteToken.balanceOf(buyer);
    
    // Calculate the buyer's total eligible balance for this cycle
    // This is their current balance minus what was already distributed in previous cycles
    uint256 newTotalEligible = currentBalance - lastIncludedBalance[buyer];
    
    // Update total eligible supply
    // Only subtract old eligible if buyer was already in this cycle
    if (!isNewBuyer) {
      totalEligible = totalEligible - eligibleBalance[buyer];
    }
    totalEligible = totalEligible + newTotalEligible;
    
    // Store the buyer's new total eligible balance
    eligibleBalance[buyer] = newTotalEligible;

    // Split revenue between distributable and retained
    uint256 distributedAmount = (amount * distributionPercentageBps) / MAX_BPS;
    uint256 retained = amount - distributedAmount;

    // Track revenue for distribution and retention
    distributableRevenue[token] += distributedAmount;
    retainedRevenue[token] += retained;

    emit PurchaseTracked(buyer, token, amount, distributedAmount, retained);
  }

  /**
   * @notice Executes distribution to consumers
   */
  function distribute() external override nonReentrant {
    if (!isCycleComplete()) revert CycleNotComplete();
    
    // Store count before it's cleared to emit correct event data
    uint256 previousBuyerCount = currentBuyers.length;
    
    // Only distribute if there are eligible buyers
    if (totalEligible > 0 && previousBuyerCount > 0) {
      // First, collect all revenue from vending machine
      _collectRevenue();
      
      // Then distribute to each buyer
      _distributeToBuyers(previousBuyerCount);
    }
    
    // Reset state for new cycle
    _resetCycleState();
    
    // Start new cycle
    _startNewCycle(previousBuyerCount);
  }

  /**
   * @notice Updates the distribution percentage
   * @param newPercentageBps New percentage in basis points
   */
  function setDistributionPercentage(uint256 newPercentageBps) external override {
    if (msg.sender != _owner) revert NotAuthorized();
    if (newPercentageBps > MAX_BPS) revert InvalidPercentage();
    
    uint256 oldPercentage = distributionPercentageBps;
    distributionPercentageBps = newPercentageBps;
    
    emit DistributionPercentageUpdated(oldPercentage, newPercentageBps);
  }

  /**
   * @notice Withdraws retained revenue
   * @param token Token to withdraw
   * @param recipient Address to receive the funds
   */
  function withdrawRetainedRevenue(address token, address recipient) external override {
    if (msg.sender != _owner) revert NotAuthorized();
    if (recipient == address(0)) revert InvalidAddress();
    
    uint256 amount = retainedRevenue[token];
    if (amount == 0) revert NoRevenueToWithdraw();
    
    retainedRevenue[token] = 0;
    
    // Collect retained revenue from vending machine
    IERC20(token).safeTransferFrom(address(vendingMachine), address(this), amount);
    
    // Transfer retained revenue to recipient
    IERC20(token).safeTransfer(recipient, amount);
    emit RetainedRevenueWithdrawn(token, amount, recipient);
  }

  /**
   * @notice Internal function to collect distributable revenue from vending machine
   */
  function _collectRevenue() internal {
    address[] memory tokens = vendingMachine.getAcceptedTokens();
    for (uint256 i = 0; i < tokens.length; i++) {
      address token = tokens[i];
      uint256 amount = distributableRevenue[token];
      
      if (amount > 0) {
        IERC20(token).safeTransferFrom(address(vendingMachine), address(this), amount);
      }
    }
  }

  /**
   * @notice Internal function to distribute revenue to all buyers
   * @param buyerCount The number of buyers in the current cycle
   */
  function _distributeToBuyers(uint256 buyerCount) internal {
    for (uint256 i = 0; i < buyerCount; i++) {
      address buyer = currentBuyers[i];
      _distributeToBuyer(buyer);
    }
  }

  /**
   * @notice Internal function to distribute revenue to a specific buyer
   * @param buyer The buyer address to pay
   */
  function _distributeToBuyer(address buyer) internal {
    uint256 buyerEligible = eligibleBalance[buyer];
    
    if (buyerEligible > 0) {
      uint256 sharePercent = (buyerEligible * 1e18) / totalEligible;
      
      _distributeTokenShareToBuyer(buyer, sharePercent);
      
      // Update last included balance to current balance
      lastIncludedBalance[buyer] = voteToken.balanceOf(buyer);
    }
    
    // Clean up buyer data
    delete eligibleBalance[buyer];
    delete isInCurrentCycle[buyer];
  }

  /**
   * @notice Internal function to distribute token shares to a buyer
   * @param buyer The buyer address
   * @param sharePercent The buyer's share percentage (scaled by 1e18)
   */
  function _distributeTokenShareToBuyer(address buyer, uint256 sharePercent) internal {
    address[] memory tokens = vendingMachine.getAcceptedTokens();
    for (uint256 j = 0; j < tokens.length; j++) {
      address token = tokens[j];
      uint256 tokenRevenue = distributableRevenue[token];
      
      if (tokenRevenue > 0) {
        uint256 tokenShare = (tokenRevenue * sharePercent) / 1e18;
        
        if (tokenShare > 0) {
          IERC20(token).safeTransfer(buyer, tokenShare);
          emit ConsumerPaid(buyer, token, tokenShare);
        }
      }
    }
  }

  /**
   * @notice Internal function to reset all cycle state
   */
  function _resetCycleState() internal {
    // Reset buyer tracking
    delete currentBuyers;
    totalEligible = 0;
    
    // Reset distributable revenue tracking
    address[] memory tokens = vendingMachine.getAcceptedTokens();
    for (uint256 i = 0; i < tokens.length; i++) {
      delete distributableRevenue[tokens[i]];
    }
  }


  /**
   * @notice Internal function to start a new cycle
   * @param previousBuyerCount The number of buyers in the previous cycle
   */
  function _startNewCycle(uint256 previousBuyerCount) internal {
    currentCycle++;
    lastCycleTimestamp = block.timestamp;
    
    emit DistributionExecuted(currentCycle - 1, previousBuyerCount, block.timestamp);
    emit NewCycleStarted(currentCycle, block.timestamp);
  }

  /**
   * @notice Checks if current cycle is complete
   */
  function isCycleComplete() public view override returns (bool) {
    return block.timestamp >= lastCycleTimestamp + cycleLength;
  }

  /**
   * @notice Gets the current cycle number
   */
  function getCurrentCycle() external view override returns (uint256) {
    return currentCycle;
  }

  /**
   * @notice Gets the number of buyers in current cycle
   */
  function getCurrentBuyerCount() external view override returns (uint256) {
    return currentBuyers.length;
  }

  /**
   * @notice Gets the current distribution percentage
   */
  function getDistributionPercentage() external view override returns (uint256) {
    return distributionPercentageBps;
  }

  /**
   * @notice Gets accumulated distributable revenue for a token
   */
  function getDistributableRevenue(address token) external view override returns (uint256) {
    return distributableRevenue[token];
  }

  /**
   * @notice Gets retained revenue for a token
   */
  function getRetainedRevenue(address token) external view override returns (uint256) {
    return retainedRevenue[token];
  }

  /**
   * @notice Gets the eligible balance for a buyer
   */
  function getEligibleBalance(address buyer) external view override returns (uint256) {
    return eligibleBalance[buyer];
  }

  /**
   * @notice Gets time until next distribution
   */
  function getTimeUntilNextDistribution() external view override returns (uint256) {
    uint256 nextDistribution = lastCycleTimestamp + cycleLength;
    if (block.timestamp >= nextDistribution) {
      return 0;
    }
    return nextDistribution - block.timestamp;
  }

  /**
   * @notice Gets the list of current buyers
   */
  function getCurrentBuyers() external view returns (address[] memory) {
    return currentBuyers;
  }

  /**
   * @notice Gets the list of allowed tokens from the vending machine
   */
  function getAllowedTokens() external view returns (address[] memory) {
    return vendingMachine.getAcceptedTokens();
  }

  /**
   * @notice Gets the contract owner address
   */
  function owner() external view override returns (address) {
    return _owner;
  }
}