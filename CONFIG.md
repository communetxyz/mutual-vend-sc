# Deployment Configuration

The deployment script now uses JSON configuration files instead of hardcoded values. This allows for flexible and maintainable deployment configurations across different networks.

## Configuration Structure

Configuration files are stored in the `config/` directory with the following structure:

```json
{
  "numTracks": 3,                    // Number of product tracks
  "maxStockPerTrack": 8,             // Maximum stock per track
  "tokenName": "Vending Machine Token",
  "tokenSymbol": "VMT",
  "acceptedTokens": [                // Array of accepted token addresses
    "0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8"
  ],
  "products": [                      // Array of initial products
    {
      "name": "Product Name",
      "ipfsHash": "ipfs://QmHash",
      "stock": 8,
      "price": "2000000000000000000"  // Price in wei (string format)
    }
  ]
}
```

## Network Configuration Files

- `config/mainnet.json` - Ethereum mainnet (chain ID: 1)
- `config/holesky.json` - Holesky testnet (chain ID: 17000)
- `config/local.json` - Local development (chain ID: 31337)

## Custom Configuration

You can specify a custom configuration file using the `CONFIG_FILE` environment variable:

```bash
CONFIG_FILE=custom.json forge script script/DeployVendingMachine.s.sol:DeployVendingMachine --rpc-url $RPC_URL --broadcast
```

## Configuration Validation

The deployment script validates the configuration before deployment:

- `numTracks` must be greater than 0
- `maxStockPerTrack` must be greater than 0
- Token name and symbol cannot be empty
- Number of products cannot exceed number of tracks
- Each product must have valid name, IPFS hash, stock, and price
- Product stock cannot exceed `maxStockPerTrack`

## Example Deployment

```bash
# Deploy to Holesky testnet (automatically uses config/holesky.json)
forge script script/DeployVendingMachine.s.sol:DeployVendingMachine \
  --rpc-url $HOLESKY_RPC_URL \
  --broadcast \
  --verify

# Deploy with custom configuration
CONFIG_FILE=my-config.json forge script script/DeployVendingMachine.s.sol:DeployVendingMachine \
  --rpc-url $RPC_URL \
  --broadcast
```