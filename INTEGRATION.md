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

## Notes

- The deployment artifact is created on every deployment to Gnosis Chain
- For production, use releases (tagged versions) rather than PR deployments
- The artifact includes all necessary metadata for frontend integration
- Consider caching the deployment data to reduce API calls
- Always verify the chain ID before interacting with contracts