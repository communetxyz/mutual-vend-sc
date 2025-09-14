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

## Deployment

### Quick Start

```bash
# 1. Configure environment variables
cp .env.example .env
# Edit .env with your RPC URLs and private keys

# 2. Deploy to Sepolia testnet
forge script script/DeployVendingMachine.s.sol:DeployVendingMachine \
  --rpc-url $SEPOLIA_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  -vvv
```

### GitHub Actions Deployment

The project includes automated deployment workflows:

1. **Configure Repository Secrets**:
   - `DEPLOYER_PRIVATE_KEY` - Private key for deployments
   - `SEPOLIA_RPC_URL` - Sepolia RPC endpoint
   - `ETHERSCAN_API_KEY` - For contract verification

2. **Trigger Deployment**:
   - Manual: Go to Actions tab → "Deploy to Sepolia" → Run workflow
   - Automatic: On pull requests and pushes to `main` branch

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for detailed deployment instructions.

## Usage

### Key Functions

#### For Operators

- `loadTrack(trackId, product, initialStock)` - Load a single track with product
- `loadMultipleTracks(trackIds[], products[], initialStocks[])` - Batch load multiple tracks
- `restockTrack(trackId, additionalStock)` - Add more items to a track
- `setTrackPrice(trackId, dollarPrice)` - Update product price for a track
- `configurePaymentTokens(tokens[])` - Set accepted stablecoins

#### For Customers

- `vendFromTrack(trackId, token, recipient)` - Purchase item from specific track

### Making a Purchase on Sepolia

To purchase from the VendingMachine on Sepolia testnet:

```bash
# Prerequisites: Get Sepolia USDC
# You need Sepolia USDC tokens. The token address is:
# 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238

# Set environment variables
export PRIVATE_KEY=your_private_key
export SEPOLIA_RPC=your_sepolia_rpc_url
export VENDING_MACHINE_ADDRESS=deployed_contract_address

# Option 1: Use the convenience script
./scripts/purchase-sepolia.sh

# Option 2: Use forge directly
forge script script/PurchaseFromVendingMachine.s.sol:PurchaseFromVendingMachine \
  --rpc-url $SEPOLIA_RPC \
  --broadcast \
  -vvv
```

The purchase script will:
1. Check your USDC balance
2. Approve the VendingMachine to spend USDC
3. Purchase from track 1 (Coca Cola)
4. Display the vote tokens received

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
