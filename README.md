# Smart Contract Vending Machine

A trust-minimized blockchain vending machine implementation that accepts stablecoin payments and issues participation tokens to customers.

## Overview

This project implements a decentralized vending machine smart contract system with the following features:

- **Multi-track vending system**: Configurable number of tracks (default: 3) for different products
- **Stablecoin payments**: Accepts multiple dollar-denominated tokens (USDC, USDT, DAI)
- **Participation tokens**: Issues ERC20 voting tokens proportional to purchase amounts
- **Sequential dispensing**: Mimics physical vending machine behavior with front-item vending
- **Role-based access control**: Separate roles for operators and treasury management

## Contracts

### VendingMachine.sol
The main vending machine contract that handles:
- Track management (loading products, setting prices, restocking)
- Payment token configuration
- Product vending with sequential dispensing
- Revenue withdrawal

### VoteToken.sol
An ERC20 token with voting capabilities that:
- Implements ERC20Votes for governance participation
- Includes permit functionality for gasless approvals
- Mints tokens proportional to customer purchases

## Installation

```bash
# Install dependencies
yarn install

# Build contracts
yarn build

# Run tests
yarn test
```

## Usage

### Deploy Contracts

```bash
# Deploy to local network
forge script script/Deploy.s.sol --rpc-url localhost --broadcast

# Deploy to Sepolia testnet
yarn deploy:sepolia
```

### Key Functions

#### For Operators

- `loadTrack(trackId, product, initialStock)` - Load a single track with product
- `loadMultipleTracks(trackIds[], products[], initialStocks[])` - Batch load multiple tracks
- `restockTrack(trackId, additionalStock)` - Add more items to a track
- `setTrackPrice(trackId, dollarPrice)` - Update product price for a track
- `configurePaymentTokens(tokens[])` - Set accepted stablecoins

#### For Customers

- `vendFromTrack(trackId, token, recipient)` - Purchase item from specific track

#### For Treasury

- `withdrawRevenue(token, to, amount)` - Withdraw collected payments

## Testing

Run the comprehensive test suite:

```bash
# Run all tests
yarn test

# Run specific test contract
forge test --match-contract VendingMachineTest

# Run with gas reporting
forge test --gas-report
```

## Architecture

The system follows a modular architecture:

1. **Access Control**: Role-based permissions for operators and treasury
2. **Reentrancy Protection**: Guards against reentrancy attacks on vending function
3. **Sequential Dispensing**: Tracks maintain FIFO inventory with automatic front-item vending
4. **Token Integration**: Safe ERC20 operations using OpenZeppelin's SafeERC20

## Security Considerations

- Uses OpenZeppelin's battle-tested contracts for core functionality
- Implements reentrancy guards on state-changing functions
- Role-based access control for administrative functions
- Input validation on all external functions
- Safe math operations (Solidity 0.8.20+)

## License

MIT
