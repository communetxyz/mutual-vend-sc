# Multi-Stocker Revenue Sharing Design

## Overview
This document describes the multi-stocker revenue sharing implementation that allows different products in the vending machine to have different stockers, each receiving their own configured share of revenue.

## Problem Statement
The vending machine needs to support a marketplace model where different vendors (stockers) can stock different products, each receiving their configured share of the revenue from their specific products.

## Current Implementation

### Key Features
1. **Per-Product Stocker Addresses**: Each product in the vending machine has its own designated stocker who receives the revenue share.
2. **Per-Product Revenue Shares**: Each product maintains its own `stockerShareBps` (basis points) for flexible revenue distribution.
3. **Dynamic Stocker Assignment**: When an operator restocks a track, they become the new stocker for that track and can set their revenue share.
4. **Multiple Stockers Tracking**: The TreasuryDistributor tracks multiple stockers efficiently using:
   - `stockerRevenue[stocker][token]` mapping for per-stocker, per-token revenue
   - `stockersWithRevenue` array to track active stockers in the current cycle
   - `hasStockerRevenue` mapping to prevent duplicate entries

### Data Structures

#### Updated Product Struct in VendingMachine
```solidity
struct Product {
    string name;
    string imageURI;
    uint256 stockerShareBps;  // stocker's revenue share in basis points (e.g., 2000 = 20%)
    address stockerAddress;   // address that receives stocker share for this product
}
```

#### TreasuryDistributor Storage
```solidity
address[] public stockersWithRevenue;                             // array of stockers with revenue in current cycle
mapping(address => mapping(address => uint256)) public stockerRevenue;  // stocker => token => amount
mapping(address => bool) public hasStockerRevenue;                // stocker => has revenue in current cycle
```

### Flow
1. **Product Configuration**: When a product is set (deployment or `loadTrack`), stocker address and share are configured.
2. **Restocking**: When `restockTrack` is called:
   - The caller becomes the new stocker for that track
   - They can set their desired revenue share percentage
   - Events are emitted for stocker changes
3. **Purchase**: During `vendFromTrack`, the VendingMachine:
   - Accepts payment and mints vote tokens
   - Calls `TreasuryDistributor.onPurchase()` with product's stocker info
4. **Distribution**: Each stocker receives their accumulated revenue across all their products

### Implementation Changes

#### VendingMachine Contract
- Product struct includes `stockerAddress` field
- Constructor validates stocker addresses are not zero
- `_loadTrack` validates stocker configuration
- `restockTrack` updates stocker to msg.sender and allows setting revenue share
- `vendFromTrack` passes stocker info to TreasuryDistributor

#### TreasuryDistributor Contract
- Tracks revenue per stocker per token
- `onPurchase` accepts stocker address parameter
- Distribution iterates through all stockers with revenue
- Reset functions clear stocker-specific data

#### Interfaces
- `ITreasuryDistributor.onPurchase()` includes stocker address parameter
- `IVendingMachine.Product` includes stocker fields
- New events: `StockerChanged`, updated `TrackRestocked`

### Benefits
1. **Marketplace Model**: Supports multiple vendors in the same vending machine
2. **Flexible Revenue**: Each product can have different revenue sharing terms
3. **Incentivized Restocking**: Operators who restock become stockers and earn revenue
4. **Transparent Tracking**: Clear visibility of who earns what from each product

### Complexity Considerations
1. **Gas Costs**: Iterating through multiple stockers during distribution
2. **State Management**: More complex tracking of stocker revenues
3. **Testing**: Need to verify stocker changes and multi-stocker distributions
4. **Initialization**: TreasuryDistributor uses initializer pattern for upgradability

## Alternative: Simple Single-Stocker Design
A simpler alternative would be:
- Single stocker address for the entire vending machine
- Single revenue share percentage applied to all products
- No stocker changes on restocking
- Simpler distribution logic with lower gas costs

## Decision
After implementation and review, the decision was made to revert to the simpler single-stocker design to reduce complexity and gas costs while maintaining the core revenue sharing functionality.