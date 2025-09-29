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
 * @notice Distributes vending machine revenue to vote token holders with per-product stocker shares
 * @dev Uses cycle-based distribution with pre-calculated revenue splits
 */
contract TreasuryDistributor is ITreasuryDistributor, ReentrancyGuard, Initializable {
  using SafeERC20 for IERC20;

  // State variables
  IVoteToken public voteToken;
  IVendingMachine public vendingMachine;
  uint256 public cycleLength;
  address[] public currentBuyers;
  address[] public stockersWithRevenue; // Track stockers that have revenue this cycle
  
  mapping(address => uint256) public eligibleBalance;
  mapping(address => uint256) public lastIncludedBalance;
  mapping(address => bool) public isInCurrentCycle;
  mapping(address => mapping(address => uint256)) public stockerRevenue; // stocker => token => amount
  mapping(address => uint256) public consumerRevenue;
  mapping(address => bool) public isAllowedToken;
  mapping(address => bool) public hasStockerRevenue; // track which stockers have revenue

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
    
    // Sync allowed tokens with vending machine
    _syncAllowedTokens();
    
    lastCycleTimestamp = block.timestamp;
    currentCycle = 1;
  }

  /**
   * @notice Syncs allowed tokens from the vending machine
   */
  function _syncAllowedTokens() internal {
    // Get accepted tokens directly from vending machine
    // The vending machine has acceptedTokenList as a public array
    // We need to query it to get all accepted tokens
    uint256 i = 0;
    while (true) {
      try vendingMachine.acceptedTokenList(i) returns (address token) {
        if (!isAllowedToken[token]) {
          isAllowedToken[token] = true;
        }
        i++;
      } catch {
        break;
      }
    }
  }

  /**
   * @notice Called by VendingMachine on each purchase to track revenue and buyers
   */
  function onPurchase(
    address buyer,
    address token,
    uint256 amount,
    uint256 stockerShareBps,
    address stockerAddress
  ) external override {
    if (msg.sender != address(vendingMachine)) revert NotAuthorized();
    if (buyer == address(0)) revert InvalidAddress();
    if (!isAllowedToken[token]) revert InvalidAddress();
    if (amount == 0) revert InvalidAmount();
    if (stockerShareBps > 10000) revert InvalidAmount();
    if (stockerAddress == address(0)) revert InvalidAddress();

    // Add buyer to current cycle if not already added
    if (!isInCurrentCycle[buyer]) {
      currentBuyers.push(buyer);
      isInCurrentCycle[buyer] = true;
    }

    // Update eligible balance
    uint256 currentBalance = voteToken.balanceOf(buyer);
    uint256 newEligible = currentBalance > lastIncludedBalance[buyer] 
      ? currentBalance - lastIncludedBalance[buyer] 
      : 0;
    
    // Update total eligible supply
    totalEligible = totalEligible - eligibleBalance[buyer] + newEligible;
    eligibleBalance[buyer] = newEligible;

    // Split and track revenue
    uint256 stockerAmount = (amount * stockerShareBps) / 10000;
    uint256 consumerAmount = amount - stockerAmount;
    
    // Track revenue for specific stocker
    if (stockerAmount > 0) {
      // Add to stockersWithRevenue array if not already added
      if (!hasStockerRevenue[stockerAddress]) {
        stockersWithRevenue.push(stockerAddress);
        hasStockerRevenue[stockerAddress] = true;
      }
      stockerRevenue[stockerAddress][token] += stockerAmount;
    }
    consumerRevenue[token] += consumerAmount;

    emit PurchaseTracked(buyer, token, amount, stockerAmount, consumerAmount);
  }

  /**
   * @notice Executes distribution to stocker and consumers
   */
  function distribute() external override nonReentrant {
    if (!isCycleComplete()) revert CycleNotComplete();

    uint256 buyerCount = currentBuyers.length;
    
    // Distribute revenue to stockers
    _distributeStockerRevenue();
    
    // Distribute revenue to consumers
    _distributeConsumerRevenue();
    
    // Reset state for new cycle
    _resetCycleState();
    
    // Start new cycle
    _startNewCycle(buyerCount);
  }

  /**
   * @notice Internal function to distribute revenue to all stockers
   */
  function _distributeStockerRevenue() internal {
    for (uint256 i = 0; i < stockersWithRevenue.length; i++) {
      address stocker = stockersWithRevenue[i];
      _distributeToStocker(stocker);
    }
  }

  /**
   * @notice Internal function to distribute revenue to a specific stocker
   * @param stocker The stocker address to pay
   */
  function _distributeToStocker(address stocker) internal {
    for (uint256 j = 0; j < _getAcceptedTokenCount(); j++) {
      address token = vendingMachine.acceptedTokenList(j);
      uint256 stockerAmount = stockerRevenue[stocker][token];
      
      if (stockerAmount > 0) {
        _transferRevenue(token, stocker, stockerAmount);
        emit StockerPaid(stocker, token, stockerAmount);
      }
    }
  }

  /**
   * @notice Internal function to distribute consumer revenue
   */
  function _distributeConsumerRevenue() internal {
    if (totalEligible == 0) return;
    
    // First, collect all consumer revenue from vending machine
    _collectConsumerRevenue();
    
    // Then distribute to each buyer
    _distributeToBuyers();
  }

  /**
   * @notice Internal function to collect consumer revenue from vending machine
   */
  function _collectConsumerRevenue() internal {
    // Iterate through all tokens that have consumer revenue
    // We don't need to maintain allowedTokens array since we track via consumerRevenue mapping
    for (uint256 i = 0; i < _getAcceptedTokenCount(); i++) {
      address token = vendingMachine.acceptedTokenList(i);
      uint256 consumerAmount = consumerRevenue[token];
      
      if (consumerAmount > 0) {
        IERC20(token).safeTransferFrom(address(vendingMachine), address(this), consumerAmount);
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
      
      // Update last included balance
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
      uint256 tokenConsumerRevenue = consumerRevenue[token];
      
      if (tokenConsumerRevenue > 0) {
        uint256 tokenShare = (tokenConsumerRevenue * sharePercent) / 1e18;
        
        if (tokenShare > 0) {
          IERC20(token).safeTransfer(buyer, tokenShare);
          emit ConsumerPaid(buyer, token, tokenShare);
        }
      }
    }
  }

  /**
   * @notice Internal function to transfer revenue from vending machine
   * @param token The token to transfer
   * @param to The recipient address
   * @param amount The amount to transfer
   */
  function _transferRevenue(address token, address to, uint256 amount) internal {
    // Transfer from vending machine to this contract
    IERC20(token).safeTransferFrom(address(vendingMachine), address(this), amount);
    // Transfer to recipient
    IERC20(token).safeTransfer(to, amount);
  }

  /**
   * @notice Internal function to reset all cycle state
   */
  function _resetCycleState() internal {
    // Reset buyer tracking
    delete currentBuyers;
    totalEligible = 0;
    
    // Reset stocker revenue tracking
    _resetStockerRevenue();
    
    // Reset consumer revenue tracking
    _resetConsumerRevenue();
  }

  /**
   * @notice Internal function to reset stocker revenue tracking
   */
  function _resetStockerRevenue() internal {
    for (uint256 i = 0; i < stockersWithRevenue.length; i++) {
      address stocker = stockersWithRevenue[i];
      for (uint256 j = 0; j < _getAcceptedTokenCount(); j++) {
        address token = vendingMachine.acceptedTokenList(j);
        delete stockerRevenue[stocker][token];
      }
      delete hasStockerRevenue[stocker];
    }
    delete stockersWithRevenue;
  }

  /**
   * @notice Internal function to reset consumer revenue tracking
   */
  function _resetConsumerRevenue() internal {
    for (uint256 i = 0; i < _getAcceptedTokenCount(); i++) {
      address token = vendingMachine.acceptedTokenList(i);
      delete consumerRevenue[token];
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
   * @notice Gets accumulated stocker revenue for a specific stocker and token
   * @param stocker The stocker address
   * @param token The token address
   */
  function getStockerRevenue(address stocker, address token) external view returns (uint256) {
    return stockerRevenue[stocker][token];
  }
  
  /**
   * @notice Gets total stocker revenue for a token across all stockers
   * @param token The token address
   */
  function getTotalStockerRevenue(address token) external view returns (uint256) {
    uint256 total = 0;
    for (uint256 i = 0; i < stockersWithRevenue.length; i++) {
      total += stockerRevenue[stockersWithRevenue[i]][token];
    }
    return total;
  }

  /**
   * @notice Gets accumulated consumer revenue for a token
   */
  function getConsumerRevenue(address token) external view override returns (uint256) {
    return consumerRevenue[token];
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
  
  /**
   * @notice Gets the list of stockers with revenue in current cycle
   */
  function getStockersWithRevenue() external view returns (address[] memory) {
    return stockersWithRevenue;
  }
}