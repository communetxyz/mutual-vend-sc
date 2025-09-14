# VendingMachine Deployment Guide

## Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Environment Setup](#environment-setup)
- [Local Deployment](#local-deployment)
- [Testnet Deployment](#testnet-deployment)
- [GitHub Actions Deployment](#github-actions-deployment)
- [Post-Deployment](#post-deployment)
- [Troubleshooting](#troubleshooting)

## Overview

This guide covers the deployment process for the VendingMachine smart contracts to various networks including local development, testnets (Holesky, Sepolia), and production environments.

## Prerequisites

1. **Node.js & Yarn**
   ```bash
   node --version  # v18.0.0 or higher
   yarn --version  # v1.22.0 or higher
   ```

2. **Foundry**
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

3. **Git**
   ```bash
   git --version  # v2.0.0 or higher
   ```

## Environment Setup

### 1. Clone the Repository

```bash
git clone https://github.com/communetxyz/mutual-vend-sc.git
cd mutual-vend-sc
```

### 2. Install Dependencies

```bash
yarn install
forge install
```

### 3. Configure Environment Variables

Create a `.env` file in the project root:

```bash
cp .env.example .env
```

Edit `.env` with your configuration:

```env
# RPC URLs
MAINNET_RPC=https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY
HOLESKY_RPC=https://eth-holesky.g.alchemy.com/v2/YOUR_API_KEY
SEPOLIA_RPC=https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY
LOCAL_RPC=http://localhost:8545

# Private Keys (NEVER commit these!)
PRIVATE_KEY=your_private_key_here
DEPLOYER_PRIVATE_KEY=your_deployer_private_key_here

# Etherscan API (for contract verification)
ETHERSCAN_API_KEY=your_etherscan_api_key_here

# Optional: Custom configuration
NUM_TRACKS=10
MAX_STOCK_PER_TRACK=100
TOKEN_NAME="Vending Machine Token"
TOKEN_SYMBOL="VMT"
```

⚠️ **Security Warning**: Never commit private keys to version control. Use environment variables or secure key management systems in production.

## Local Deployment

### 1. Start Local Node

```bash
# In a separate terminal
anvil --fork-url $HOLESKY_RPC
```

### 2. Deploy Contracts

```bash
# Deploy to local node
forge script script/DeployVendingMachine.s.sol:DeployVendingMachine \
  --rpc-url http://localhost:8545 \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvv
```

### 3. Verify Deployment

The script will output:
- VendingMachine contract address
- VoteToken contract address
- Configuration details

## Testnet Deployment

### Holesky Testnet

```bash
# Deploy to Holesky
forge script script/DeployVendingMachine.s.sol:DeployVendingMachine \
  --rpc-url $HOLESKY_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --slow \
  -vvv
```

### Sepolia Testnet

```bash
# Deploy to Sepolia
forge script script/DeployVendingMachine.s.sol:DeployVendingMachine \
  --rpc-url $SEPOLIA_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --slow \
  -vvv
```

## GitHub Actions Deployment

### 1. Configure Repository Secrets

Go to your repository's Settings > Secrets and variables > Actions, and add:

| Secret Name | Description | Example |
|------------|-------------|---------|
| `DEPLOYER_PRIVATE_KEY` | Private key for deployment | `0x...` (64 hex chars) |
| `DEPLOYER_ADDRESS` | Address of the deployer | `0x...` (40 hex chars) |
| `HOLESKY_RPC_URL` | Holesky RPC endpoint | `https://eth-holesky.g.alchemy.com/v2/...` |
| `SEPOLIA_RPC_URL` | Sepolia RPC endpoint | `https://eth-sepolia.g.alchemy.com/v2/...` |
| `ETHERSCAN_API_KEY` | For contract verification | Your Etherscan API key |

### 2. Trigger Deployment

#### Manual Deployment
1. Go to Actions tab in GitHub
2. Select "Deploy to Testnet" workflow
3. Click "Run workflow"
4. Select network (holesky/sepolia)
5. Choose whether to verify contracts
6. Click "Run workflow"

#### Automatic Deployment
Deployments are automatically triggered when:
- Pushing to `main` branch (deploys to Holesky)
- Pushing to `develop` branch (deploys to Sepolia)

### 3. Monitor Deployment

The workflow will:
1. Build contracts
2. Deploy VendingMachine and VoteToken
3. Verify contracts on Etherscan (if enabled)
4. Generate deployment summary
5. Save deployment artifacts

## Post-Deployment

### 1. Verify Contracts

If automatic verification fails:

```bash
forge verify-contract \
  --chain-id 17000 \
  --watch \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --constructor-args $(cast abi-encode "constructor(uint8,uint256,string,string,address[],tuple[],uint256[],uint256[])" 10 100 "Vending Machine Token" "VMT" "[]" "[]" "[]" "[]") \
  CONTRACT_ADDRESS \
  src/contracts/VendingMachine.sol:VendingMachine
```

### 2. Configure Contract

After deployment, configure the VendingMachine:

```solidity
// Example: Load products into tracks
cast send $VENDING_MACHINE_ADDRESS \
  "loadTrack(uint8,(string,string),uint256)" \
  0 "(\"Coca Cola\",\"ipfs://QmCocaCola\")" 10 \
  --private-key $PRIVATE_KEY \
  --rpc-url $HOLESKY_RPC

// Set track prices
cast send $VENDING_MACHINE_ADDRESS \
  "setTrackPrice(uint8,uint256)" \
  0 2000000000000000000 \
  --private-key $PRIVATE_KEY \
  --rpc-url $HOLESKY_RPC

// Configure accepted payment tokens
cast send $VENDING_MACHINE_ADDRESS \
  "configurePaymentTokens(address[])" \
  "[0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8]" \
  --private-key $PRIVATE_KEY \
  --rpc-url $HOLESKY_RPC
```

### 3. Grant Roles

```solidity
// Grant operator role
cast send $VENDING_MACHINE_ADDRESS \
  "grantRole(bytes32,address)" \
  $(cast keccak "OPERATOR_ROLE()") \
  $OPERATOR_ADDRESS \
  --private-key $PRIVATE_KEY \
  --rpc-url $HOLESKY_RPC

// Grant treasury role
cast send $VENDING_MACHINE_ADDRESS \
  "grantRole(bytes32,address)" \
  $(cast keccak "TREASURY_ROLE()") \
  $TREASURY_ADDRESS \
  --private-key $PRIVATE_KEY \
  --rpc-url $HOLESKY_RPC
```

## Troubleshooting

### Common Issues

1. **"Insufficient funds" error**
   - Ensure your deployer account has enough ETH for gas
   - Holesky faucet: https://holesky-faucet.pk910.de/
   - Sepolia faucet: https://sepoliafaucet.com/

2. **"Contract verification failed"**
   - Check Etherscan API key is correct
   - Wait a few minutes and retry
   - Manually verify using the command above

3. **"RPC error"**
   - Check RPC URL is correct and accessible
   - Verify API key limits haven't been exceeded
   - Try using a different RPC provider

4. **"Nonce too low"**
   - Reset account nonce: `cast nonce $DEPLOYER_ADDRESS --rpc-url $RPC_URL`
   - Wait for pending transactions to complete

### Deployment Checklist

- [ ] Environment variables configured
- [ ] Sufficient ETH for gas
- [ ] Repository secrets configured (for CI/CD)
- [ ] Network RPC accessible
- [ ] Etherscan API key valid
- [ ] Initial products/prices configured in script
- [ ] Post-deployment configuration planned

## Network Information

| Network | Chain ID | Currency | Explorer |
|---------|----------|----------|----------|
| Holesky | 17000 | ETH | https://holesky.etherscan.io |
| Sepolia | 11155111 | ETH | https://sepolia.etherscan.io |
| Local | 31337 | ETH | N/A |

## Support

For issues or questions:
- Create an issue on [GitHub](https://github.com/communetxyz/mutual-vend-sc/issues)
- Check existing [deployments](https://github.com/communetxyz/mutual-vend-sc/deployments)
- Review [workflow runs](https://github.com/communetxyz/mutual-vend-sc/actions)