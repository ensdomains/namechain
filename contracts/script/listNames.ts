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
const dedicatedResolverPath = join(process.cwd(), "deployments", "l2-local", "DedicatedResolverImpl.json");
const l1RootRegistryPath = join(process.cwd(), "deployments", "l1-local", "RootRegistry.json");
const rootRegistryDeployment = JSON.parse(readFileSync(rootRegistryPath, "utf8"));
const l1EthRegistryDeployment = JSON.parse(readFileSync(l1EthRegistryPath, "utf8"));
const ethRegistryDeployment = JSON.parse(readFileSync(ethRegistryPath, "utf8"));
const l1RegistryDatastoreDeployment = JSON.parse(readFileSync(l1RegistryDatastorePath, "utf8"));
const l2RegistryDatastoreDeployment = JSON.parse(readFileSync(l2RegistryDatastorePath, "utf8"));
const dedicatedResolverDeployment = JSON.parse(readFileSync(dedicatedResolverPath, "utf8"));
const l1RootRegistryDeployment = JSON.parse(readFileSync(l1RootRegistryPath, "utf8"));

// Extract ABIs for events
const registryEvents = l1EthRegistryDeployment.abi.filter((item: any) => item.type === "event");
const datastoreEvents = l1RegistryDatastoreDeployment.abi.filter((item: any) => item.type === "event");
const resolverEvents = dedicatedResolverDeployment.abi.filter((item: any) => item.type === "event");

// Helper function to create registry key
function createRegistryKey(chainId: number, address: string): string {
  return `${chainId}-${address.toLowerCase()}`;
}

// Initialize maps for tracking relationships
const labelHashToLabel = new Map<string, string>();
const labelHashToParentRegistry = new Map<string, string>();
const allRegistries = new Set<string>();
const allResolvers = new Map<string, {
  address: string;
  addresses: Map<string, string>;
  texts: Map<string, string>;
}>();

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

// Fetch historical logs from L1 Registry
const l1RegistryLogs = await l1Client.getLogs({
  address: l1EthRegistryDeployment.address,
  fromBlock: 0n,
  toBlock: await l1Client.getBlockNumber(),
});

console.log("L1 Registry logs:", l1RegistryLogs.length);

// Process L1 Registry events
for (const log of l1RegistryLogs) {
  const decoded = decodeEvent(log, registryEvents);
  console.log("Decoded L1 event:", decoded?.eventName, decoded?.args);
  
  if (decoded && typeof decoded.args === 'object' && decoded.args !== null) {
    if (decoded.eventName === "SubregistryUpdate") {
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
            registry: args.subregistry.toLowerCase(),
            resolver: "0x0000000000000000000000000000000000000000",
            label: label
          });
        }
        
        allRegistries.add(registryKey);
        allRegistries.add(subregistryKey);
        labelHashToParentRegistry.set(labelHash, registryKey);
      }
    } else if (decoded.eventName === "ResolverUpdate") {
      const args = decoded.args as unknown as ResolverUpdateEventArgs;
      const registryKey = createRegistryKey(l1Chain.id, args.registry);
      const labelHash = args.id.toString();
      const resolver = args.resolver.toLowerCase();
      
      if (resolver && resolver !== "0x0000000000000000000000000000000000000000") {
        // Track resolver
        allResolvers.set(resolver, {
          address: resolver,
          addresses: new Map(),
          texts: new Map()
        });

        // Update registry node
        const registryNode = registryTree.get(registryKey);
        if (registryNode) {
          const label = labelHashToLabel.get(labelHash) || '';
          registryNode.labels.set(labelHash, {
            registry: args.registry.toLowerCase(),
            resolver: resolver,
            label: label
          });
        }

        // Fetch AddressChanged events for this resolver
        const resolverLogs = await l1Client.getLogs({
          address: resolver as `0x${string}`,
          fromBlock: 0n,
          toBlock: await l1Client.getBlockNumber(),
        });
        for (const log of resolverLogs) {
          const decodedEvent = decodeEvent(log, resolverEvents);
          if (decodedEvent && decodedEvent.eventName === "AddressChanged" && typeof decodedEvent.args === 'object' && decodedEvent.args !== null) {
            const addressArgs = decodedEvent.args as unknown as AddressChangedEventArgs;
            const resolverInfo = allResolvers.get(resolver)!;
            resolverInfo.addresses.set(addressArgs.coinType?.toString() || "60", addressArgs.newAddress);
          }
          if (decodedEvent && decodedEvent.eventName === "TextChanged" && typeof decodedEvent.args === 'object' && decodedEvent.args !== null) {
            const textArgs = decodedEvent.args as unknown as TextChangedEventArgs;
            const resolverInfo = allResolvers.get(resolver)!;
            resolverInfo.texts.set(textArgs.key, textArgs.value);
          }
        }
      }
    }
  }
}

// Fetch historical logs from L2 Registry
const l2RegistryLogs = await l2Client.getLogs({
  address: ethRegistryDeployment.address,
  fromBlock: 0n,
  toBlock: await l2Client.getBlockNumber(),
});

console.log("L2 Registry logs:", l2RegistryLogs.length);

// Process L2 Registry events
for (const log of l2RegistryLogs) {
  const decoded = decodeEvent(log, registryEvents);
  console.log("Decoded L2 event:", decoded?.eventName, decoded?.args);
  
  if (decoded && typeof decoded.args === 'object' && decoded.args !== null) {
    if (decoded.eventName === "SubregistryUpdate") {
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
            registry: args.subregistry.toLowerCase(),
            resolver: "0x0000000000000000000000000000000000000000",
            label: label
          });
        }
        
        allRegistries.add(registryKey);
        allRegistries.add(subregistryKey);
        labelHashToParentRegistry.set(labelHash, registryKey);
      }
    } else if (decoded.eventName === "ResolverUpdate") {
      const args = decoded.args as unknown as ResolverUpdateEventArgs;
      const registryKey = createRegistryKey(l2Chain.id, args.registry);
      const labelHash = args.id.toString();
      const resolver = args.resolver.toLowerCase();
      
      if (resolver && resolver !== "0x0000000000000000000000000000000000000000") {
        // Track resolver
        allResolvers.set(resolver, {
          address: resolver,
          addresses: new Map(),
          texts: new Map()
        });

        // Update registry node
        const registryNode = registryTree.get(registryKey);
        if (registryNode) {
          const label = labelHashToLabel.get(labelHash) || '';
          registryNode.labels.set(labelHash, {
            registry: args.registry.toLowerCase(),
            resolver: resolver,
            label: label
          });
        }

        // Fetch AddressChanged events for this resolver
        const resolverLogs = await l2Client.getLogs({
          address: resolver as `0x${string}`,
          fromBlock: 0n,
          toBlock: await l2Client.getBlockNumber(),
        });
        for (const log of resolverLogs) {
          const decodedEvent = decodeEvent(log, resolverEvents);
          if (decodedEvent && decodedEvent.eventName === "AddressChanged" && typeof decodedEvent.args === 'object' && decodedEvent.args !== null) {
            const addressArgs = decodedEvent.args as unknown as AddressChangedEventArgs;
            const resolverInfo = allResolvers.get(resolver)!;
            resolverInfo.addresses.set(addressArgs.coinType?.toString() || "60", addressArgs.newAddress);
          }
          if (decodedEvent && decodedEvent.eventName === "TextChanged" && typeof decodedEvent.args === 'object' && decodedEvent.args !== null) {
            const textArgs = decodedEvent.args as unknown as TextChangedEventArgs;
            const resolverInfo = allResolvers.get(resolver)!;
            resolverInfo.texts.set(textArgs.key, textArgs.value);
          }
        }
      }
    }
  }
}

// Fetch historical logs from L1 RootRegistry
const l1RootRegistryLogs = await l1Client.getLogs({
  address: l1RootRegistryDeployment.address,
  fromBlock: 0n,
  toBlock: await l1Client.getBlockNumber(),
});

console.log("L1 RootRegistry logs:", l1RootRegistryLogs.length);

// Process L1 RootRegistry events
for (const log of l1RootRegistryLogs) {
  const decoded = decodeEvent(log, registryEvents);
  console.log("Decoded L1 RootRegistry event:", decoded?.eventName, decoded?.args);
  
  if (decoded && typeof decoded.args === 'object' && decoded.args !== null) {
    if (decoded.eventName === "SubregistryUpdate") {
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
            registry: args.subregistry.toLowerCase(),
            resolver: "0x0000000000000000000000000000000000000000",
            label: label
          });
        }
        
        allRegistries.add(registryKey);
        allRegistries.add(subregistryKey);
        labelHashToParentRegistry.set(labelHash, registryKey);
      }
    } else if (decoded.eventName === "ResolverUpdate") {
      const args = decoded.args as unknown as ResolverUpdateEventArgs;
      const registryKey = createRegistryKey(l1Chain.id, args.registry);
      const labelHash = args.id.toString();
      const resolver = args.resolver.toLowerCase();
      
      if (resolver && resolver !== "0x0000000000000000000000000000000000000000") {
        // Track resolver
        allResolvers.set(resolver, {
          address: resolver,
          addresses: new Map(),
          texts: new Map()
        });

        // Update registry node
        const registryNode = registryTree.get(registryKey);
        if (registryNode) {
          const label = labelHashToLabel.get(labelHash) || '';
          registryNode.labels.set(labelHash, {
            registry: args.registry.toLowerCase(),
            resolver: resolver,
            label: label
          });
        }

        // Fetch AddressChanged events for this resolver
        const resolverLogs = await l1Client.getLogs({
          address: resolver as `0x${string}`,
          fromBlock: 0n,
          toBlock: await l1Client.getBlockNumber(),
        });
        for (const log of resolverLogs) {
          const decodedEvent = decodeEvent(log, resolverEvents);
          if (decodedEvent && decodedEvent.eventName === "AddressChanged" && typeof decodedEvent.args === 'object' && decodedEvent.args !== null) {
            const addressArgs = decodedEvent.args as unknown as AddressChangedEventArgs;
            const resolverInfo = allResolvers.get(resolver)!;
            resolverInfo.addresses.set(addressArgs.coinType?.toString() || "60", addressArgs.newAddress);
          }
          if (decodedEvent && decodedEvent.eventName === "TextChanged" && typeof decodedEvent.args === 'object' && decodedEvent.args !== null) {
            const textArgs = decodedEvent.args as unknown as TextChangedEventArgs;
            const resolverInfo = allResolvers.get(resolver)!;
            resolverInfo.texts.set(textArgs.key, textArgs.value);
          }
        }
      }
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

interface ResolverUpdateEventArgs {
  registry: `0x${string}`;
  id: bigint;
  resolver: `0x${string}`;
  expiry: bigint;
  data: number;
}

interface AddressChangedEventArgs {
  node: `0x${string}`;
  coinType: bigint;
  newAddress: `0x${string}`;
}

interface TextChangedEventArgs {
  node: `0x${string}`;
  key: string;
  value: string;
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

// Update RegistryNode interface
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
console.log("\nAll Registered Names with Resolver Information:");
console.log("--------------------------------");
allNames.forEach(name => {
  console.log(`\nName: ${name}`);
  
  // Find the labelHash for this name
  const labelHash = Array.from(labelHashToLabel.entries())
    .find(([_, label]) => name === `${label}.eth`)?.[0];
  
  if (labelHash) {
    // Find the resolver for this label
    const labelResolver = Array.from(registryTree.values())
      .find(node => node.labels.has(labelHash))
      ?.labels.get(labelHash)?.resolver;
    
    if (labelResolver) {
      // Only show info for the matching resolver
      const resolverInfo = allResolvers.get(labelResolver);
      if (resolverInfo) {
        console.log(`  Resolver: ${labelResolver}`);
        
        if (resolverInfo.addresses.size > 0) {
          console.log("  Addresses:");
          for (const [coinType, address] of resolverInfo.addresses.entries()) {
            console.log(`    CoinType ${coinType}: ${address}`);
          }
        }
        
        if (resolverInfo.texts.size > 0) {
          console.log("  Text Records:");
          for (const [key, value] of resolverInfo.texts.entries()) {
            console.log(`    ${key}: ${value}`);
          }
        }
      }
    }
  }
});
console.log("--------------------------------");
console.log(`Total unique names: ${allNames.length}`);

function toNullIfZeroAddress(addr: string): string | null {
  if (!addr || addr === "0x0000000000000000000000000000000000000000" || addr === "") {
    return null;
  }
  return addr;
}

// Add before the final console.log
console.log("allResolvers", allResolvers);
console.log("\nAll Resolvers and their Addresses:");
console.log("--------------------------------");
for (const [resolver, info] of allResolvers.entries()) {
  console.log(`\nResolver: ${resolver}`);
  if (info.addresses.size > 0) {
    console.log("Addresses:");
    for (const [node, address] of info.addresses.entries()) {
      console.log(`  Node: ${node} -> Address: ${address}`);
    }
  } else {
    console.log("No addresses set");
  }
}
console.log("--------------------------------");
console.log(`Total resolvers: ${allResolvers.size}`); 