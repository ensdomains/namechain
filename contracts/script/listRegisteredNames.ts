import { createPublicClient, http, parseAbiItem, decodeEventLog } from 'viem';
import { localhost } from 'viem/chains';

const RPC_URL = 'http://localhost:8546';
const ETH_REGISTRAR_ADDRESS = '0xa513e6e4b8f2a923d98304ec87f64353c4d5c853';

const client = createPublicClient({
  chain: localhost,
  transport: http(RPC_URL),
});

const nameRegisteredEvent = parseAbiItem(
  'event NameRegistered(string name, address owner, address subregistry, address resolver, uint64 duration, uint256 tokenId, uint256 baseCost, uint256 premium)'
);

function shortenAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

async function listRegisteredNames() {
  console.log('Fetching all registered names...\n');

  try {
    const logs = await client.getLogs({
      address: ETH_REGISTRAR_ADDRESS as `0x${string}`,
      event: nameRegisteredEvent,
      fromBlock: 0n,
      toBlock: 'latest',
    });

    console.log(`Found ${logs.length} registered names\n`);

    if (logs.length === 0) {
      console.log('No names found');
      return;
    }

    const namesData = logs.map((log, index) => {
      try {
        const decoded = decodeEventLog({
          abi: [nameRegisteredEvent],
          data: log.data,
          topics: log.topics,
        });
        
        const { name, owner, duration, baseCost, premium } = decoded.args;
        const totalCost = Number(baseCost) + Number(premium);
        const durationInDays = Math.floor(Number(duration) / 86400);
        
        return {
          '#': index + 1,
          'Name': name,
          'Owner': shortenAddress(owner),
          'Duration (days)': durationInDays,
          'Total Cost (USD)': (totalCost / 1e8).toFixed(2),
        };
      } catch (error) {
        return {
          '#': index + 1,
          'Name': 'Error decoding',
          'Owner': 'Error',
          'Duration (days)': 'Error',
          'Total Cost (USD)': 'Error',
        };
      }
    });

    console.table(namesData);

    console.log('\nSummary:');
    console.log('===========');
    
    const uniqueOwners = new Set(namesData.map(item => item.Owner).filter(owner => owner !== 'Error'));
    const totalCost = namesData
      .filter(item => item['Total Cost (USD)'] !== 'Error')
      .reduce((sum, item) => sum + parseFloat(item['Total Cost (USD)']), 0);
    
    console.log(`Total Names: ${namesData.length}`);
    console.log(`Unique Owners: ${uniqueOwners.size}`);
    console.log(`Total Value: $${totalCost.toFixed(2)} USD`);

  } catch (error) {
    console.error('Error fetching names:', error);
  }
}

listRegisteredNames().catch(console.error);
