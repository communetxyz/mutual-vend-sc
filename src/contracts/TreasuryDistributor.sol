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

  address[] public currentBuyers;
  
  mapping(address => uint256) public eligibleBalance;
  mapping(address => uint256) public lastIncludedBalance;
  mapping(address => bool) public isInCurrentCycle;
  mapping(address => uint256) public revenue; // token => amount

  uint256 public totalEligible;
  uint256 public currentCycle;
  uint256 public lastCycleTimestamp;

  /**
   * @notice Initializes the treasury distributor
   * @param _voteToken The vote token used for calculating distributions
   * @param _vendingMachine The vending machine contract
   * @param _cycleLength The distribution cycle length in seconds
   */
  function initialize(
    address _voteToken,
    address _vendingMachine,
    uint256 _cycleLength
  ) external initializer {
    if (_voteToken == address(0)) revert InvalidAddress();
    if (_vendingMachine == address(0)) revert InvalidAddress();
    if (_cycleLength == 0) revert InvalidCycleLength();

    voteToken = IVoteToken(_voteToken);
    vendingMachine = IVendingMachine(_vendingMachine);
    cycleLength = _cycleLength;
    
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
    if (!isInCurrentCycle[buyer]) {
      currentBuyers.push(buyer);
      isInCurrentCycle[buyer] = true;
    }

    // Get buyer's current vote token balance (already includes new tokens)
    uint256 currentBalance = voteToken.balanceOf(buyer);
    
    // Calculate new eligible balance
    // eligibleBalance = current balance - what was already included in distributions
    uint256 newEligible = currentBalance - lastIncludedBalance[buyer];
    
    // Update total eligible supply
    totalEligible = totalEligible - eligibleBalance[buyer] + newEligible;
    eligibleBalance[buyer] = newEligible;

    // Track revenue for distribution
    revenue[token] += amount;

    emit PurchaseTracked(buyer, token, amount, 0, amount);
  }

  /**
   * @notice Executes distribution to consumers
   */
  function distribute() external override nonReentrant {
    if (!isCycleComplete()) revert CycleNotComplete();

    uint256 buyerCount = currentBuyers.length;
    
    // Distribute revenue to consumers
    _distributeRevenue();
    
    // Reset state for new cycle
    _resetCycleState();
    
    // Start new cycle
    _startNewCycle(buyerCount);
  }

  /**
   * @notice Internal function to distribute revenue
   */
  function _distributeRevenue() internal {
    if (totalEligible == 0) return;
    
    // First, collect all revenue from vending machine
    _collectRevenue();
    
    // Then distribute to each buyer
    _distributeToBuyers();
  }

  /**
   * @notice Internal function to collect revenue from vending machine
   */
  function _collectRevenue() internal {
    for (uint256 i = 0; i < _getAcceptedTokenCount(); i++) {
      address token = vendingMachine.acceptedTokenList(i);
      uint256 amount = revenue[token];
      
      if (amount > 0) {
        IERC20(token).safeTransferFrom(address(vendingMachine), address(this), amount);
      }
    }
  }

  /**
   * @notice Internal function to distribute revenue to all buyers
   */
  function _distributeToBuyers() internal {
    uint256 buyerCount = currentBuyers.length;
    
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
    for (uint256 j = 0; j < _getAcceptedTokenCount(); j++) {
      address token = vendingMachine.acceptedTokenList(j);
      uint256 tokenRevenue = revenue[token];
      
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
    
    // Reset revenue tracking
    _resetRevenue();
  }

  /**
   * @notice Internal function to reset revenue tracking
   */
  function _resetRevenue() internal {
    for (uint256 i = 0; i < _getAcceptedTokenCount(); i++) {
      address token = vendingMachine.acceptedTokenList(i);
      delete revenue[token];
    }
  }

  /**
   * @notice Internal function to get the count of accepted tokens from vending machine
   */
  function _getAcceptedTokenCount() internal view returns (uint256 count) {
    // Count tokens by trying to access the array until it reverts
    while (true) {
      try vendingMachine.acceptedTokenList(count) returns (address) {
        count++;
      } catch {
        break;
      }
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
   * @notice Gets accumulated stocker revenue for a token (deprecated - always returns 0)
   */
  function getStockerRevenue(address) external pure override returns (uint256) {
    return 0;
  }

  /**
   * @notice Gets accumulated consumer revenue for a token
   */
  function getConsumerRevenue(address token) external view override returns (uint256) {
    return revenue[token];
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
    uint256 count = _getAcceptedTokenCount();
    address[] memory tokens = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      tokens[i] = vendingMachine.acceptedTokenList(i);
    }
    return tokens;
  }
}