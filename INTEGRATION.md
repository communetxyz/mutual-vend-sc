# Frontend Integration Guide

## Fetching Latest Deployment Addresses

The deployment workflow automatically creates a `deployment-gnosis.json` artifact that contains all the necessary information for frontend integration.

### Method 1: Direct GitHub API

Fetch the latest release and download the deployment artifact:

```javascript
// Fetch latest deployment addresses from GitHub
async function getLatestDeployment() {
  try {
    // Get latest release
    const releaseResponse = await fetch(
      'https://api.github.com/repos/communetxyz/mutual-vend-sc/releases/latest'
    );
    const release = await releaseResponse.json();
    
    // Find the deployment artifact
    const deploymentAsset = release.assets.find(
      asset => asset.name === 'deployment-gnosis.json'
    );
    
    if (!deploymentAsset) {
      throw new Error('Deployment artifact not found');
    }
    
    // Download the deployment artifact
    const artifactResponse = await fetch(deploymentAsset.browser_download_url);
    const deployment = await artifactResponse.json();
    
    return deployment;
  } catch (error) {
    console.error('Failed to fetch deployment:', error);
    throw error;
  }
}

// Usage
const deployment = await getLatestDeployment();
console.log('VendingMachine address:', deployment.contracts.vendingMachine);
console.log('VoteToken address:', deployment.contracts.voteToken);
console.log('Chain ID:', deployment.chainId);
console.log('RPC URL:', deployment.metadata.rpcUrl);
```

### Method 2: Using GitHub Actions API

Fetch from the latest successful workflow run:

```javascript
async function getDeploymentFromWorkflow() {
  // Get latest successful workflow run
  const workflowResponse = await fetch(
    'https://api.github.com/repos/communetxyz/mutual-vend-sc/actions/workflows/deploy-gnosis.yml/runs?status=success&per_page=1'
  );
  const { workflow_runs } = await workflowResponse.json();
  
  if (!workflow_runs.length) {
    throw new Error('No successful deployments found');
  }
  
  const latestRun = workflow_runs[0];
  
  // Get artifacts from the workflow run
  const artifactsResponse = await fetch(latestRun.artifacts_url);
  const { artifacts } = await artifactsResponse.json();
  
  const deploymentArtifact = artifacts.find(
    a => a.name.startsWith('deployment-gnosis-')
  );
  
  // Note: Downloading artifacts requires authentication
  // For public access, use Method 1 (releases) instead
  return deploymentArtifact;
}
```

### Method 3: Static CDN (Recommended for Production)

Host the deployment artifact on a CDN that auto-updates from GitHub releases:

```javascript
// Using jsDelivr CDN (auto-updates from GitHub)
async function getDeploymentFromCDN() {
  const response = await fetch(
    'https://cdn.jsdelivr.net/gh/communetxyz/mutual-vend-sc@latest/deployment-gnosis.json'
  );
  return await response.json();
}
```

## Deployment Artifact Structure

The `deployment-gnosis.json` file contains:

```typescript
interface DeploymentArtifact {
  network: 'gnosis';
  chainId: 100;
  contracts: {
    vendingMachine: string;  // Contract address
    voteToken: string;       // Token contract address
  };
  transactions: {
    deployment: string;      // Deployment transaction hash
    testPurchase?: string;   // Test purchase transaction hash
  };
  metadata: {
    timestamp: string;       // ISO 8601 timestamp
    commitHash: string;      // Git commit hash
    deployer: string;        // Deployer address
    rpcUrl: string;          // Recommended RPC endpoint
    explorerUrl: string;     // Block explorer URL
    acceptedTokens: string[]; // Array of accepted token addresses
  };
  version: string;           // Release version or build number
  abi: {
    vendingMachine: string;  // URL to interface file
  };
}
```

## React Hook Example

```jsx
import { useState, useEffect } from 'react';

function useVendingMachineContract() {
  const [deployment, setDeployment] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    async function fetchDeployment() {
      try {
        const response = await fetch(
          'https://api.github.com/repos/communetxyz/mutual-vend-sc/releases/latest'
        );
        const release = await response.json();
        
        const asset = release.assets.find(a => a.name === 'deployment-gnosis.json');
        if (!asset) throw new Error('Deployment not found');
        
        const deploymentResponse = await fetch(asset.browser_download_url);
        const deploymentData = await deploymentResponse.json();
        
        setDeployment(deploymentData);
      } catch (err) {
        setError(err.message);
      } finally {
        setLoading(false);
      }
    }

    fetchDeployment();
  }, []);

  return { deployment, loading, error };
}

// Usage in component
function VendingMachineApp() {
  const { deployment, loading, error } = useVendingMachineContract();

  if (loading) return <div>Loading contract addresses...</div>;
  if (error) return <div>Error: {error}</div>;

  return (
    <div>
      <h1>Vending Machine</h1>
      <p>Contract: {deployment.contracts.vendingMachine}</p>
      <p>Network: {deployment.network} (Chain {deployment.chainId})</p>
      <a 
        href={`${deployment.metadata.explorerUrl}/address/${deployment.contracts.vendingMachine}`}
        target="_blank"
        rel="noopener noreferrer"
      >
        View on Explorer
      </a>
    </div>
  );
}
```

## Ethers.js Integration

```javascript
import { ethers } from 'ethers';

async function connectToVendingMachine() {
  // Fetch deployment info
  const deployment = await getLatestDeployment();
  
  // Connect to Gnosis
  const provider = new ethers.JsonRpcProvider(deployment.metadata.rpcUrl);
  
  // Load ABI (you'll need to fetch this separately)
  const abi = await fetchVendingMachineABI();
  
  // Create contract instance
  const vendingMachine = new ethers.Contract(
    deployment.contracts.vendingMachine,
    abi,
    provider
  );
  
  // For write operations, connect signer
  const signer = await provider.getSigner();
  const vendingMachineWithSigner = vendingMachine.connect(signer);
  
  return vendingMachineWithSigner;
}
```

## Viem Integration

```javascript
import { createPublicClient, http } from 'viem';
import { gnosis } from 'viem/chains';

async function setupViem() {
  const deployment = await getLatestDeployment();
  
  const client = createPublicClient({
    chain: gnosis,
    transport: http(deployment.metadata.rpcUrl),
  });
  
  // Read from contract
  const result = await client.readContract({
    address: deployment.contracts.vendingMachine,
    abi: vendingMachineABI,
    functionName: 'getTrack',
    args: [0],
  });
  
  return result;
}
```

## Environment Variables

For local development, create a `.env` file:

```bash
# Fetched dynamically from deployment artifact
NEXT_PUBLIC_VENDING_MACHINE_ADDRESS=
NEXT_PUBLIC_VOTE_TOKEN_ADDRESS=
NEXT_PUBLIC_GNOSIS_RPC_URL=https://rpc.gnosischain.com
NEXT_PUBLIC_CHAIN_ID=100
```

Then use a script to update from the latest deployment:

```javascript
// scripts/update-env.js
const fs = require('fs');

async function updateEnv() {
  const deployment = await getLatestDeployment();
  
  const envContent = `
NEXT_PUBLIC_VENDING_MACHINE_ADDRESS=${deployment.contracts.vendingMachine}
NEXT_PUBLIC_VOTE_TOKEN_ADDRESS=${deployment.contracts.voteToken}
NEXT_PUBLIC_GNOSIS_RPC_URL=${deployment.metadata.rpcUrl}
NEXT_PUBLIC_CHAIN_ID=${deployment.chainId}
`;
  
  fs.writeFileSync('.env.local', envContent.trim());
  console.log('✅ Environment variables updated');
}

updateEnv();
```

## Python Integration

### Using requests library

```python
import requests
import json

def get_latest_deployment():
    """Fetch the latest deployment addresses from GitHub releases."""
    try:
        # Get latest release
        response = requests.get(
            'https://api.github.com/repos/communetxyz/mutual-vend-sc/releases/latest'
        )
        response.raise_for_status()
        release = response.json()
        
        # Find the deployment artifact
        deployment_asset = None
        for asset in release.get('assets', []):
            if asset['name'] == 'deployment-gnosis.json':
                deployment_asset = asset
                break
        
        if not deployment_asset:
            raise ValueError('Deployment artifact not found')
        
        # Download the deployment artifact
        artifact_response = requests.get(deployment_asset['browser_download_url'])
        artifact_response.raise_for_status()
        
        return artifact_response.json()
    
    except requests.RequestException as e:
        print(f"Failed to fetch deployment: {e}")
        raise

# Usage
deployment = get_latest_deployment()
print(f"VendingMachine address: {deployment['contracts']['vendingMachine']}")
print(f"VoteToken address: {deployment['contracts']['voteToken']}")
print(f"Chain ID: {deployment['chainId']}")
print(f"RPC URL: {deployment['metadata']['rpcUrl']}")
```

### Using async with aiohttp

```python
import aiohttp
import asyncio

async def get_latest_deployment_async():
    """Asynchronously fetch the latest deployment addresses."""
    async with aiohttp.ClientSession() as session:
        # Get latest release
        async with session.get(
            'https://api.github.com/repos/communetxyz/mutual-vend-sc/releases/latest'
        ) as response:
            release = await response.json()
        
        # Find deployment artifact
        deployment_asset = next(
            (asset for asset in release.get('assets', []) 
             if asset['name'] == 'deployment-gnosis.json'),
            None
        )
        
        if not deployment_asset:
            raise ValueError('Deployment artifact not found')
        
        # Download the artifact
        async with session.get(deployment_asset['browser_download_url']) as artifact_response:
            return await artifact_response.json()

# Usage
async def main():
    deployment = await get_latest_deployment_async()
    print(f"Contracts: {deployment['contracts']}")

asyncio.run(main())
```

### Web3.py Integration

```python
from web3 import Web3
import requests
import json

class VendingMachineClient:
    def __init__(self):
        self.deployment = self._fetch_deployment()
        self.w3 = Web3(Web3.HTTPProvider(self.deployment['metadata']['rpcUrl']))
        self.vending_machine_address = self.deployment['contracts']['vendingMachine']
        self.vote_token_address = self.deployment['contracts']['voteToken']
        
        # Load ABI (you'll need to provide this)
        self.abi = self._load_abi()
        
        # Create contract instance
        self.contract = self.w3.eth.contract(
            address=self.vending_machine_address,
            abi=self.abi
        )
    
    def _fetch_deployment(self):
        """Fetch deployment configuration from GitHub."""
        response = requests.get(
            'https://api.github.com/repos/communetxyz/mutual-vend-sc/releases/latest'
        )
        release = response.json()
        
        asset = next(
            (a for a in release['assets'] if a['name'] == 'deployment-gnosis.json'),
            None
        )
        
        if not asset:
            raise ValueError('Deployment not found')
        
        return requests.get(asset['browser_download_url']).json()
    
    def _load_abi(self):
        # Load ABI from file or fetch from GitHub
        # This is a placeholder - replace with actual ABI loading
        return []
    
    def get_track(self, track_id):
        """Get track information from the vending machine."""
        return self.contract.functions.getTrack(track_id).call()
    
    def get_balance(self, address):
        """Get vote token balance for an address."""
        vote_token = self.w3.eth.contract(
            address=self.vote_token_address,
            abi=self.abi  # Use ERC20 ABI
        )
        return vote_token.functions.balanceOf(address).call()

# Usage
client = VendingMachineClient()
track_info = client.get_track(0)
print(f"Track 0: {track_info}")
```

### Dataclass for Type Safety

```python
from dataclasses import dataclass
from typing import List, Optional, Dict
import requests
from datetime import datetime

@dataclass
class Contracts:
    vending_machine: str
    vote_token: str

@dataclass
class Transactions:
    deployment: str
    test_purchase: Optional[str] = None

@dataclass
class Metadata:
    timestamp: datetime
    commit_hash: str
    deployer: str
    rpc_url: str
    explorer_url: str
    accepted_tokens: List[str]

@dataclass
class DeploymentArtifact:
    network: str
    chain_id: int
    contracts: Contracts
    transactions: Transactions
    metadata: Metadata
    version: str
    abi: Dict[str, str]
    
    @classmethod
    def from_github(cls):
        """Fetch and parse deployment from GitHub releases."""
        response = requests.get(
            'https://api.github.com/repos/communetxyz/mutual-vend-sc/releases/latest'
        )
        release = response.json()
        
        asset = next(
            (a for a in release['assets'] if a['name'] == 'deployment-gnosis.json'),
            None
        )
        
        if not asset:
            raise ValueError('Deployment artifact not found')
        
        data = requests.get(asset['browser_download_url']).json()
        
        return cls(
            network=data['network'],
            chain_id=data['chainId'],
            contracts=Contracts(
                vending_machine=data['contracts']['vendingMachine'],
                vote_token=data['contracts']['voteToken']
            ),
            transactions=Transactions(
                deployment=data['transactions']['deployment'],
                test_purchase=data['transactions'].get('testPurchase')
            ),
            metadata=Metadata(
                timestamp=datetime.fromisoformat(data['metadata']['timestamp'].replace('Z', '+00:00')),
                commit_hash=data['metadata']['commitHash'],
                deployer=data['metadata']['deployer'],
                rpc_url=data['metadata']['rpcUrl'],
                explorer_url=data['metadata']['explorerUrl'],
                accepted_tokens=data['metadata']['acceptedTokens']
            ),
            version=data['version'],
            abi=data['abi']
        )

# Usage
deployment = DeploymentArtifact.from_github()
print(f"VendingMachine: {deployment.contracts.vending_machine}")
print(f"Deployed at: {deployment.metadata.timestamp}")
print(f"Chain: {deployment.network} (ID: {deployment.chain_id})")
```

### CLI Tool Example

```python
#!/usr/bin/env python3
"""
CLI tool to fetch and display deployment information.
Save as: get_deployment.py
"""

import argparse
import json
import requests
from typing import Optional

def get_deployment(format: str = 'json', contract: Optional[str] = None):
    """Fetch deployment information."""
    response = requests.get(
        'https://api.github.com/repos/communetxyz/mutual-vend-sc/releases/latest'
    )
    release = response.json()
    
    asset = next(
        (a for a in release['assets'] if a['name'] == 'deployment-gnosis.json'),
        None
    )
    
    if not asset:
        raise ValueError('Deployment not found')
    
    deployment = requests.get(asset['browser_download_url']).json()
    
    if contract:
        return deployment['contracts'].get(contract, 'Contract not found')
    
    if format == 'json':
        return json.dumps(deployment, indent=2)
    elif format == 'env':
        return f"""
VENDING_MACHINE_ADDRESS={deployment['contracts']['vendingMachine']}
VOTE_TOKEN_ADDRESS={deployment['contracts']['voteToken']}
GNOSIS_RPC_URL={deployment['metadata']['rpcUrl']}
CHAIN_ID={deployment['chainId']}
""".strip()
    else:
        return deployment

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Fetch Gnosis deployment addresses')
    parser.add_argument('--format', choices=['json', 'env'], default='json',
                        help='Output format')
    parser.add_argument('--contract', choices=['vendingMachine', 'voteToken'],
                        help='Get specific contract address')
    
    args = parser.parse_args()
    
    try:
        result = get_deployment(args.format, args.contract)
        print(result)
    except Exception as e:
        print(f"Error: {e}")
        exit(1)

# Usage:
# python get_deployment.py --format json
# python get_deployment.py --format env > .env
# python get_deployment.py --contract vendingMachine
```

### Environment File Generator

```python
import requests
import os
from pathlib import Path

def update_env_file(env_path: str = '.env'):
    """Update or create .env file with latest deployment addresses."""
    
    # Fetch deployment
    response = requests.get(
        'https://api.github.com/repos/communetxyz/mutual-vend-sc/releases/latest'
    )
    release = response.json()
    
    asset = next(
        (a for a in release['assets'] if a['name'] == 'deployment-gnosis.json'),
        None
    )
    
    if not asset:
        raise ValueError('Deployment not found')
    
    deployment = requests.get(asset['browser_download_url']).json()
    
    # Read existing env file if exists
    env_vars = {}
    if Path(env_path).exists():
        with open(env_path, 'r') as f:
            for line in f:
                if '=' in line and not line.startswith('#'):
                    key, value = line.strip().split('=', 1)
                    env_vars[key] = value
    
    # Update deployment-related variables
    env_vars.update({
        'VENDING_MACHINE_ADDRESS': deployment['contracts']['vendingMachine'],
        'VOTE_TOKEN_ADDRESS': deployment['contracts']['voteToken'],
        'GNOSIS_RPC_URL': deployment['metadata']['rpcUrl'],
        'GNOSIS_CHAIN_ID': str(deployment['chainId']),
        'DEPLOYMENT_VERSION': deployment['version'],
        'DEPLOYMENT_TIMESTAMP': deployment['metadata']['timestamp']
    })
    
    # Write back to file
    with open(env_path, 'w') as f:
        f.write('# Auto-generated Gnosis deployment configuration\n')
        for key, value in env_vars.items():
            f.write(f'{key}={value}\n')
    
    print(f"✅ Updated {env_path} with latest deployment")
    return env_vars

# Usage
env_vars = update_env_file()
print(f"VendingMachine: {env_vars['VENDING_MACHINE_ADDRESS']}")
```

## Notes

- The deployment artifact is created on every deployment to Gnosis Chain
- For production, use releases (tagged versions) rather than PR deployments
- The artifact includes all necessary metadata for frontend integration
- Consider caching the deployment data to reduce API calls
- Always verify the chain ID before interacting with contracts