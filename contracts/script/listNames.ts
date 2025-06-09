import { createPublicClient, http, type Chain, getContract, type Log, decodeEventLog, type Abi, type DecodeEventLogReturnType } from "viem";
import { readFileSync } from "fs";
import { join } from "path";

// Add debug flag at the top of the file
const DEBUG = false;

// Define chain types
const l1Chain: Chain = {
  id: 31337,
  name: "Local L1",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: ["http://127.0.0.1:8545"] },
    public: { http: ["http://127.0.0.1:8545"] },
  },
};

const l2Chain: Chain = {
  id: 31338,
  name: "Local L2",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: ["http://127.0.0.1:8546"] },
    public: { http: ["http://127.0.0.1:8546"] },
  },
};

// Connect to the networks
const l1Client = createPublicClient({
  chain: l1Chain,
  transport: http(),
});

const l2Client = createPublicClient({
  chain: l2Chain,
  transport: http(),
});

// Read deployment files
const rootRegistryPath = join(process.cwd(), "deployments", "l1-local", "RootRegistry.json");
const l1EthRegistryPath = join(process.cwd(), "deployments", "l1-local", "L1ETHRegistry.json");
const ethRegistryPath = join(process.cwd(), "deployments", "l2-local", "ETHRegistry.json");
const l1RegistryDatastorePath = join(process.cwd(), "deployments", "l1-local", "RegistryDatastore.json");
const l2RegistryDatastorePath = join(process.cwd(), "deployments", "l2-local", "RegistryDatastore.json");

const rootRegistryDeployment = JSON.parse(readFileSync(rootRegistryPath, "utf8"));
const l1EthRegistryDeployment = JSON.parse(readFileSync(l1EthRegistryPath, "utf8"));
const ethRegistryDeployment = JSON.parse(readFileSync(ethRegistryPath, "utf8"));
const l1RegistryDatastoreDeployment = JSON.parse(readFileSync(l1RegistryDatastorePath, "utf8"));
const l2RegistryDatastoreDeployment = JSON.parse(readFileSync(l2RegistryDatastorePath, "utf8"));

// Extract ABIs for events
const registryEvents = l1EthRegistryDeployment.abi.filter((item: any) => item.type === "event");
const datastoreEvents = l1RegistryDatastoreDeployment.abi.filter((item: any) => item.type === "event");

// Helper function to create registry key
function createRegistryKey(chainId: number, address: string): string {
  return `${chainId}-${address.toLowerCase()}`;
}

// Initialize maps for tracking relationships
const labelHashToLabel = new Map<string, string>();
const labelHashToParentRegistry = new Map<string, string>();
const allRegistries = new Set<string>();

// Add initial registries
allRegistries.add(createRegistryKey(l1Chain.id, rootRegistryDeployment.address));
allRegistries.add(createRegistryKey(l1Chain.id, l1EthRegistryDeployment.address));
allRegistries.add(createRegistryKey(l2Chain.id, ethRegistryDeployment.address));

// Process NewSubname events to populate labelHashToLabel
for (const registry of allRegistries) {
  if (registry === "0x0000000000000000000000000000000000000000") continue;
  const [chainId, address] = registry.split('-');
  const client = parseInt(chainId) === l1Chain.id ? l1Client : l2Client;
  let logs: Log[] = [];
  try {
    logs = await client.getLogs({
      address: address as `0x${string}`,
      fromBlock: 0n,
      toBlock: await client.getBlockNumber(),
    });
  } catch (e) {
    continue;
  }
  for (const log of logs) {
    const decoded = decodeEvent(log, registryEvents);
    if (decoded && decoded.eventName === "NewSubname" && typeof decoded.args === 'object' && decoded.args !== null) {
      const args = decoded.args as unknown as NewSubnameEventArgs;
      if (args.labelHash !== undefined && args.label !== undefined) {
        const labelHash = args.labelHash.toString();
        const label = args.label;
        labelHashToLabel.set(labelHash, label);
      }
    }
  }
}

// Initialize registry tree with chain information
const registryTree = new Map<string, { subregistries: Set<string>, chainId: number, expiry: number, labels: Map<string, { registry: string; resolver: string; label: string }> }>();

// Add root registry
registryTree.set(createRegistryKey(l1Chain.id, rootRegistryDeployment.address), {
  subregistries: new Set<string>(),
  chainId: l1Chain.id,
  expiry: 0,
  labels: new Map()
});

// Add L1 ETH Registry
registryTree.set(createRegistryKey(l1Chain.id, l1EthRegistryDeployment.address), {
  subregistries: new Set<string>(),
  chainId: l1Chain.id,
  expiry: 0,
  labels: new Map()
});

// Add L2 ETH Registry
registryTree.set(createRegistryKey(l2Chain.id, ethRegistryDeployment.address), {
  subregistries: new Set<string>(),
  chainId: l2Chain.id,
  expiry: 0,
  labels: new Map()
});

// Establish L1-L2 registry relationship
const l1EthRegistry = registryTree.get(createRegistryKey(l1Chain.id, l1EthRegistryDeployment.address));
if (l1EthRegistry) {
  l1EthRegistry.subregistries.add(createRegistryKey(l2Chain.id, ethRegistryDeployment.address));
}


// Fetch historical logs from L1 RegistryDatastore
const l1DatastoreLogs = await l1Client.getLogs({
  address: l1RegistryDatastoreDeployment.address,
  fromBlock: 0n,
  toBlock: await l1Client.getBlockNumber(),
});

console.log("L1 Datastore logs:", l1DatastoreLogs.length);

// Process L1 RegistryDatastore events
for (const log of l1DatastoreLogs) {
  const decoded = decodeEvent(log, datastoreEvents);
  console.log("Decoded L1 event:", decoded?.eventName, decoded?.args);
  
  if (decoded && decoded.eventName === "SubregistryUpdate" && typeof decoded.args === 'object' && decoded.args !== null) {
    const args = decoded.args as unknown as SubregistryUpdateEventArgs;
    const registryKey = createRegistryKey(l1Chain.id, args.registry);
    const subregistryKey = createRegistryKey(l1Chain.id, args.subregistry);
    const labelHash = args.id.toString();
    const expiry = Number(args.expiry);
    
    if (expiry > Math.floor(Date.now() / 1000)) {
      if (!registryTree.has(registryKey)) {
        registryTree.set(registryKey, {
          subregistries: new Set(),
          chainId: l1Chain.id,
          expiry: 0,
          labels: new Map()
        });
      }
      
      const registryNode = registryTree.get(registryKey)!;
      registryNode.subregistries.add(subregistryKey);
      registryNode.expiry = expiry;
      
      // Add label information
      const label = labelHashToLabel.get(labelHash);
      if (label) {
        registryNode.labels.set(labelHash, {
          registry: toNullIfZeroAddress(args.subregistry) as string | null,
          resolver: toNullIfZeroAddress("0x0000000000000000000000000000000000000000") as string | null,
          label: label
        });
      }
      
      allRegistries.add(registryKey);
      allRegistries.add(subregistryKey);
      labelHashToParentRegistry.set(labelHash, registryKey);
    }
  }
}

// Fetch historical logs from L2 RegistryDatastore
const l2DatastoreLogs = await l2Client.getLogs({
  address: l2RegistryDatastoreDeployment.address,
  fromBlock: 0n,
  toBlock: await l2Client.getBlockNumber(),
});

console.log("L2 Datastore logs:", l2DatastoreLogs.length);

// Process L2 RegistryDatastore events
for (const log of l2DatastoreLogs) {
  const decoded = decodeEvent(log, datastoreEvents);
  console.log("Decoded L2 event:", decoded?.eventName, decoded?.args);
  
  if (decoded && decoded.eventName === "SubregistryUpdate" && typeof decoded.args === 'object' && decoded.args !== null) {
    const args = decoded.args as unknown as SubregistryUpdateEventArgs;
    const registryKey = createRegistryKey(l2Chain.id, args.registry);
    const subregistryKey = createRegistryKey(l2Chain.id, args.subregistry);
    const labelHash = args.id.toString();
    const expiry = Number(args.expiry);
    
    if (expiry > Math.floor(Date.now() / 1000)) {
      if (!registryTree.has(registryKey)) {
        registryTree.set(registryKey, {
          subregistries: new Set(),
          chainId: l2Chain.id,
          expiry: 0,
          labels: new Map()
        });
      }
      
      const registryNode = registryTree.get(registryKey)!;
      registryNode.subregistries.add(subregistryKey);
      registryNode.expiry = expiry;
      
      // Add label information
      const label = labelHashToLabel.get(labelHash);
      if (label) {
        registryNode.labels.set(labelHash, {
          registry: toNullIfZeroAddress(args.subregistry) as string | null,
          resolver: toNullIfZeroAddress("0x0000000000000000000000000000000000000000") as string | null,
          label: label
        });
      }
      
      allRegistries.add(registryKey);
      allRegistries.add(subregistryKey);
      labelHashToParentRegistry.set(labelHash, registryKey);
    }
  }
}

// Convert registry tree to plain object for logging
const registryTreePlain = convertToPlainObject(registryTree);
console.log("Final registry tree:", JSON.stringify(registryTreePlain, null, 2));


// Convert labelHashToLabel to plain object and log
const labelHashToLabelPlain = Object.fromEntries(labelHashToLabel);
console.log("\nLabel Hash to Label Mappings:", JSON.stringify(labelHashToLabelPlain, null, 2));

// Show SubregistryUpdate events for the 'eth' labelHash
console.log('\nSubregistryUpdate Events for eth:');
console.log('--------------------------------');
for (const [registryKey, registryInfo] of registryTree.entries()) {
  if (registryInfo.labels.size > 0) {
    console.log('\nSubregistryUpdate Event:');
    console.log('----------------------');
    console.log('Registry:', registryKey);
    for (const [labelHash, labelInfo] of registryInfo.labels.entries()) {
      console.log('LabelHash:', labelHash);
      console.log('Label:', labelInfo.label);
      console.log('Expiry:', new Date(registryInfo.expiry * 1000)?.toLocaleString());
    }
    console.log('----------------------');
  }
}

// Event types
interface SubregistryUpdateEventArgs {
  registry: `0x${string}`;
  id: bigint; // This is labelHash
  subregistry: `0x${string}`;
  expiry: bigint;
  data: number;
}

interface NewSubnameEventArgs {
  labelHash: bigint;
  label: string;
}

type LabelHash = string;
type RegistryAddress = string;

function decodeEvent(log: Log, abi: Abi): DecodeEventLogReturnType | null {
  try {
    return decodeEventLog({
      abi,
      data: log.data,
      topics: log.topics,
    });
  } catch (error) {
    return null;
  }
}

async function listNames() {
  console.log("Fetching names from registry events...\n");

  // Get current block numbers
  const l1Block = await l1Client.getBlockNumber();
  const l2Block = await l2Client.getBlockNumber();


  // Get all SubregistryUpdate events from both L1 and L2 RegistryDatastore
  const l1DatastoreLogs = await l1Client.getLogs({
    address: l1RegistryDatastoreDeployment.address,
    fromBlock: 0n,
    toBlock: l1Block,
  });
  const l2DatastoreLogs = await l2Client.getLogs({
    address: l2RegistryDatastoreDeployment.address,
    fromBlock: 0n,
    toBlock: l2Block,
  });

  // Build registry tree: registry -> [{labelHash, subregistry, expiry}]
  const registryTree = new Map<RegistryAddress, { labelHash: LabelHash; subregistry: RegistryAddress; expiry: number }[]>();
  // Set of all discovered registries
  const allRegistries = new Set<RegistryAddress>();
  // Map labelHash -> parent registry
  const labelHashToParentRegistry = new Map<LabelHash, RegistryAddress>();

  // Parse SubregistryUpdate events
  for (const log of [...l1DatastoreLogs, ...l2DatastoreLogs]) {
    const decoded = decodeEvent(log, datastoreEvents);
    if (decoded && decoded.eventName === "SubregistryUpdate" && typeof decoded.args === 'object' && decoded.args !== null) {
      const args = decoded.args as unknown as SubregistryUpdateEventArgs;
      const registry = args.registry.toLowerCase();
      const subregistry = args.subregistry.toLowerCase();
      const labelHash = args.id.toString();
      const expiry = Number(args.expiry);
      
      if (expiry > Math.floor(Date.now() / 1000)) {
        if (!registryTree.has(registry)) registryTree.set(registry, []);
        registryTree.get(registry)!.push({ labelHash, subregistry, expiry });
        allRegistries.add(registry);
        allRegistries.add(subregistry);
        labelHashToParentRegistry.set(labelHash, registry);
      }
    }
  }

  // For each discovered registry, get all NewSubname events and build labelHash -> label map
  const labelHashToLabel = new Map<LabelHash, string>();
  for (const registry of allRegistries) {
    if (registry === "0x0000000000000000000000000000000000000000") continue;
    const l1Addresses = [l1EthRegistryDeployment.address, rootRegistryDeployment.address].map(addr => addr.toLowerCase());
    const client = l1Addresses.includes(registry.toLowerCase())
      ? l1Client
      : l2Client;
    let logs: Log[] = [];
    try {
      logs = await client.getLogs({
        address: registry as `0x${string}`,
        fromBlock: 0n,
        toBlock: await client.getBlockNumber(),
      });
    } catch (e) {
      continue;
    }
    for (const log of logs) {
      const decoded = decodeEvent(log, registryEvents);
      if (decoded && decoded.eventName === "NewSubname" && typeof decoded.args === 'object' && decoded.args !== null) {
        const args = decoded.args as unknown as NewSubnameEventArgs;
        if (args.labelHash !== undefined && args.label !== undefined) {
          const labelHash = args.labelHash.toString();
          const label = args.label;
          labelHashToLabel.set(labelHash, label);
          
          // Debug: Show events with 'eth' label
          if (label === 'eth') {
            console.log('\nNewSubname Event:');
            console.log('----------------');
            console.log('Registry:', registry);
            console.log('Label:', label);
            console.log('LabelHash:', labelHash);
            console.log('Block:', log.blockNumber);
            console.log('Transaction:', log.transactionHash);
            console.log('Raw Log:', log);
            console.log('Decoded Args:', args);
            console.log('----------------');
          }
        } else {
          console.warn('Malformed NewSubname event args:', args, 'log:', log);
        }
      }
    }
  }

  // Recursively build full names
  function buildFullName(labelHash: LabelHash): string | null {
    const label = labelHashToLabel.get(labelHash);
    if (!label) return null;
    const parentRegistry = labelHashToParentRegistry.get(labelHash);
    if (!parentRegistry || parentRegistry === rootRegistryDeployment.address.toLowerCase()) {
      return `${label}.eth`;
    }
    // Find the parent labelHash that links this registry to its parent
    const parentLinks = registryTree.get(parentRegistry) || [];
    for (const link of parentLinks) {
      if (link.subregistry === labelHashToParentRegistry.get(labelHash)) {
        const parentName = buildFullName(link.labelHash);
        if (parentName) return `${label}.${parentName}`;
      }
    }
    // Fallback: just return label
    return label;
  }
  // Collect all full names
  const fullNames = new Set<string>();
  for (const [labelHash, label] of labelHashToLabel.entries()) {
    const fullName = buildFullName(labelHash);
    if (fullName) fullNames.add(fullName);
  }

  if (DEBUG) {
    console.log("Registered Names:");
    console.log("----------------");
    if (fullNames.size === 0) {
      console.log("No names found in registry events.");
    } else {
      Array.from(fullNames).sort().forEach(name => {
        console.log(`- ${name}`);
      });
    }
    console.log("----------------");
    console.log(`Total unique names: ${fullNames.size}`);
  }
}

listNames().catch(console.error);

// Helper function to convert Map/Set to plain object
function convertToPlainObject(obj: any): any {
  if (obj instanceof Map) {
    const plainObj: any = {};
    for (const [key, value] of obj.entries()) {
      plainObj[key] = convertToPlainObject(value);
    }
    return plainObj;
  } else if (obj instanceof Set) {
    return Array.from(obj);
  } else if (obj && typeof obj === 'object') {
    const plainObj: any = {};
    for (const [key, value] of Object.entries(obj)) {
      plainObj[key] = convertToPlainObject(value);
    }
    return plainObj;
  }
  return obj;
}

// New RegistryNode interface
interface RegistryNode {
  subregistries: Set<string>;
  chainId: number;
  expiry: number;
  labels: Map<string, {
    registry: string | null;
    resolver: string | null;
    label: string;
  }>;
}

// Update collectNames to use the new structure
function collectNames(
  registryKey: string,
  registryTree: Map<string, RegistryNode>,
  currentPath: string[] = []
): string[] {
  const registry = registryTree.get(registryKey);
  if (!registry) return [];

  const names: string[] = [];
  let newPath = currentPath;

  // Process labels in the current registry
  for (const [labelHash, labelInfo] of registry.labels.entries()) {
    const label = labelInfo.label;
    newPath = [label, ...currentPath];
    names.push(newPath.join('.'));
  }

  // Traverse subregistries
  for (const subregistryKey of registry.subregistries) {
    const subNames = collectNames(subregistryKey, registryTree, newPath);
    names.push(...subNames);
  }

  return names;
}

// Update the name collection call
const allNames = collectNames(
  `${l1Chain.id}-${rootRegistryDeployment.address}`,
  registryTree
).filter(name => name != 'eth');
console.log("\nAll Registered Names:");
console.log("----------------");
allNames.forEach(name => console.log(`- ${name}`));
console.log("----------------");
console.log(`Total unique names: ${allNames.length}`);

function toNullIfZeroAddress(addr: string): string | null {
  if (!addr || addr === "0x0000000000000000000000000000000000000000" || addr === "") {
    return null;
  }
  return addr;
} 