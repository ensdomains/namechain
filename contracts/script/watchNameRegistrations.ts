import { createPublicClient, http, parseAbiItem, decodeEventLog } from 'viem';
import { localhost } from 'viem/chains';

const RPC_URL = 'http://localhost:8546';
const ETH_REGISTRAR_ADDRESS = '0xa513e6e4b8f2a923d98304ec87f64353c4d5c853';
const POLL_INTERVAL = 2000;

const client = createPublicClient({
  chain: localhost,
  transport: http(RPC_URL),
});

const nameRegisteredEvent = parseAbiItem(
  'event NameRegistered(string name, address owner, address subregistry, address resolver, uint64 duration, uint256 tokenId, uint256 baseCost, uint256 premium)'
);

const processedEvents = new Set<string>();

const colors = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m',
  white: '\x1b[37m',
  red: '\x1b[31m',
};

function log(message: string, color: keyof typeof colors = 'reset') {
  const timestamp = new Date().toLocaleTimeString();
  console.log(`${colors[color]}[${timestamp}] ${message}${colors.reset}`);
}

function displayNewRegistration(name: string, owner: string, baseCost: string, premium: string) {
  const totalCost = Number(baseCost) + Number(premium);
  const costInUSD = (totalCost / 1e8).toFixed(2);
  
  log('NEW NAME REGISTERED!', 'green');
  log('======================', 'green');
  log(`Name: ${colors.bright}${name}${colors.reset}`, 'white');
  log(`Owner: ${colors.cyan}${owner}${colors.reset}`, 'white');
  log(`Total Cost: ${colors.yellow}$${costInUSD}${colors.reset}`, 'white');
  
  if (Number(premium) > 0) {
    log(`   └─ Base: $${(Number(baseCost) / 1e8).toFixed(2)} | Premium: $${(Number(premium) / 1e8).toFixed(2)}`, 'white');
  }
  log('');
}

async function checkForNewRegistrations() {
  try {
    const logs = await client.getLogs({
      address: ETH_REGISTRAR_ADDRESS as `0x${string}`,
      event: nameRegisteredEvent,
      fromBlock: 0n,
      toBlock: 'latest',
    });

    logs.forEach(log => {
      const eventKey = `${log.transactionHash}-${log.logIndex}`;
      
      if (!processedEvents.has(eventKey)) {
        try {
          const decoded = decodeEventLog({
            abi: [nameRegisteredEvent],
            data: log.data,
            topics: log.topics,
          });
          
          const { name, owner, baseCost, premium } = decoded.args;
          
          displayNewRegistration(
            name,
            owner,
            baseCost.toString(),
            premium.toString()
          );
          
          processedEvents.add(eventKey);
          
        } catch (error) {
          // Skip invalid logs
        }
      }
    });

  } catch (error) {
    log(`Error checking for new registrations: ${error}`, 'red');
  }
}

async function watchRegistrations() {
  log('Starting Name Registration Monitor...', 'green');
  log(`Watching ETHRegistrar: ${ETH_REGISTRAR_ADDRESS}`, 'blue');
  log(`Polling every ${POLL_INTERVAL / 1000} seconds`, 'blue');
  log('Try registering a new name to see it here!', 'yellow');
  log('Press Ctrl+C to stop monitoring\n', 'yellow');

  try {
    log('Loading existing registrations...', 'cyan');
    const existingLogs = await client.getLogs({
      address: ETH_REGISTRAR_ADDRESS as `0x${string}`,
      event: nameRegisteredEvent,
      fromBlock: 0n,
      toBlock: 'latest',
    });

    log(`Found ${existingLogs.length} existing registrations (will show new ones only)`, 'cyan');
    
    existingLogs.forEach(log => {
      const eventKey = `${log.transactionHash}-${log.logIndex}`;
      processedEvents.add(eventKey);
    });

    log('\nMonitoring for new registrations...', 'green');
    
    const pollInterval = setInterval(async () => {
      await checkForNewRegistrations();
    }, POLL_INTERVAL);

    process.on('SIGINT', () => {
      log('\nStopping monitor...', 'yellow');
      clearInterval(pollInterval);
      process.exit(0);
    });

  } catch (error) {
    log(`Error setting up monitor: ${error}`, 'red');
  }
}

watchRegistrations().catch(console.error);
