import { readFileSync, readdirSync } from 'fs';
import { join } from 'path';

interface Deployment {
  address?: string;
  abi?: any[];
  receipt?: {
    from: string;
    contractAddress: string;
    transactionHash: string;
    blockNumber: number;
  };
}

function readDeploymentFile(filePath: string): Deployment | null {
  try {
    const content = readFileSync(filePath, 'utf-8');
    return JSON.parse(content);
  } catch (error) {
    console.error(`Error reading file ${filePath}:`, error);
    return null;
  }
}

function formatAddress(address: string | undefined): string {
  if (!address) return 'N/A';
  return address;
}

async function main() {
  console.log('Listing deployed contracts from local test networks...\n');

  // Read L1 deployments
  console.log('L1 Deployments:');
  console.log('==============');
  const l1Path = join(process.cwd(), 'deployments', 'l1-local');
  try {
    const l1Files = readdirSync(l1Path).filter(file => file.endsWith('.json'));
    
    for (const file of l1Files) {
      const deployment = readDeploymentFile(join(l1Path, file));
      if (!deployment) continue;
      
      const contractName = file.replace('.json', '');
      console.log(`${contractName}:`);
      console.log(`  Address: ${formatAddress(deployment.address)}`);
      if (deployment.receipt) {
        console.log(`  Deployed by: ${formatAddress(deployment.receipt.from)}`);
        console.log(`  Transaction: ${deployment.receipt.transactionHash}`);
        console.log(`  Block: ${deployment.receipt.blockNumber}`);
      }
      console.log('');
    }
  } catch (error) {
    console.error('Error reading L1 deployments:', error);
  }

  // Read L2 deployments
  console.log('L2 Deployments:');
  console.log('==============');
  const l2Path = join(process.cwd(), 'deployments', 'l2-local');
  try {
    const l2Files = readdirSync(l2Path).filter(file => file.endsWith('.json'));
    
    for (const file of l2Files) {
      const deployment = readDeploymentFile(join(l2Path, file));
      if (!deployment) continue;
      
      const contractName = file.replace('.json', '');
      console.log(`${contractName}:`);
      console.log(`  Address: ${formatAddress(deployment.address)}`);
      if (deployment.receipt) {
        console.log(`  Deployed by: ${formatAddress(deployment.receipt.from)}`);
        console.log(`  Transaction: ${deployment.receipt.transactionHash}`);
        console.log(`  Block: ${deployment.receipt.blockNumber}`);
      }
      console.log('');
    }
  } catch (error) {
    console.error('Error reading L2 deployments:', error);
  }
}

main().catch((error) => {
  console.error('Error:', error);
  process.exit(1);
}); 