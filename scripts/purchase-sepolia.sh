#!/bin/bash

# Script to purchase from VendingMachine on Sepolia testnet
# Prerequisites:
# 1. PRIVATE_KEY environment variable set with deployer private key
# 2. SEPOLIA_RPC environment variable set with RPC URL
# 3. VENDING_MACHINE_ADDRESS environment variable set with deployed contract address
# 4. Deployer address must have Sepolia USDC balance

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}VendingMachine Purchase Script - Sepolia${NC}"
echo -e "${GREEN}=========================================${NC}"

# Check required environment variables
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}Error: PRIVATE_KEY environment variable not set${NC}"
    exit 1
fi

if [ -z "$SEPOLIA_RPC" ]; then
    echo -e "${RED}Error: SEPOLIA_RPC environment variable not set${NC}"
    exit 1
fi

if [ -z "$VENDING_MACHINE_ADDRESS" ]; then
    echo -e "${YELLOW}Warning: VENDING_MACHINE_ADDRESS not set${NC}"
    echo "You can set it with: export VENDING_MACHINE_ADDRESS=0x..."
    echo "Or pass it as the first argument to this script"
    
    if [ -n "$1" ]; then
        export VENDING_MACHINE_ADDRESS=$1
        echo -e "${GREEN}Using VendingMachine address: $VENDING_MACHINE_ADDRESS${NC}"
    else
        echo -e "${RED}Error: Please provide VendingMachine address${NC}"
        exit 1
    fi
fi

# USDC Token on Sepolia
SEPOLIA_USDC="0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"

echo -e "${YELLOW}Configuration:${NC}"
echo "  VendingMachine: $VENDING_MACHINE_ADDRESS"
echo "  USDC Token: $SEPOLIA_USDC"
echo "  RPC URL: $SEPOLIA_RPC"
echo ""

# Get deployer address from private key
DEPLOYER_ADDRESS=$(cast wallet address $PRIVATE_KEY)
echo -e "${YELLOW}Deployer Address: $DEPLOYER_ADDRESS${NC}"

# Check USDC balance
echo -e "\n${YELLOW}Checking USDC balance...${NC}"
USDC_BALANCE=$(cast call $SEPOLIA_USDC "balanceOf(address)(uint256)" $DEPLOYER_ADDRESS --rpc-url $SEPOLIA_RPC)
USDC_BALANCE_DECIMAL=$(cast to-dec $USDC_BALANCE)
USDC_BALANCE_ETHER=$(cast to-unit $USDC_BALANCE_DECIMAL ether)

echo "USDC Balance: $USDC_BALANCE_ETHER USDC"

if [ "$USDC_BALANCE_DECIMAL" -eq "0" ]; then
    echo -e "${RED}Error: No USDC balance found${NC}"
    echo "Please get some Sepolia USDC from a faucet or mint it first"
    echo "USDC Contract: https://sepolia.etherscan.io/address/$SEPOLIA_USDC"
    exit 1
fi

# Run the purchase script
echo -e "\n${GREEN}Executing purchase...${NC}"
forge script script/PurchaseFromVendingMachine.s.sol:PurchaseFromVendingMachine \
    --rpc-url $SEPOLIA_RPC \
    --broadcast \
    --slow \
    -vvv

echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}Purchase completed successfully!${NC}"
echo -e "${GREEN}=========================================${NC}"