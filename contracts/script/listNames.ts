import { createPublicClient, http, type Chain, getContract, type Log, decodeEventLog, type Abi, type DecodeEventLogReturnType } from "viem";
import { readFileSync } from "fs";
import { join } from "path";
import * as ethers from "ethers";

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

// Remove datastore-related imports and variables
const l1RootRegistryPath = join(process.cwd(), "deployments", "l1-local", "RootRegistry.json");
const l1EthRegistryPath = join(process.cwd(), "deployments", "l1-local", "L1ETHRegistry.json");
const l2EthRegistryPath = join(process.cwd(), "deployments", "l2-local", "ETHRegistry.json");
const userRegistryImplPath = join(process.cwd(), "deployments", "l2-local", "UserRegistryImpl.json");
const dedicatedResolverPath = join(process.cwd(), "deployments", "l2-local", "DedicatedResolverImpl.json");

// Load deployment artifacts
const rootRegistryDeployment = JSON.parse(readFileSync(l1RootRegistryPath, "utf8"));
const l1EthRegistryDeployment = JSON.parse(readFileSync(l1EthRegistryPath, "utf8"));
const ethRegistryDeployment = JSON.parse(readFileSync(l2EthRegistryPath, "utf8"));
const userRegistryImplDeployment = JSON.parse(readFileSync(userRegistryImplPath, "utf8"));
const dedicatedResolverDeployment = JSON.parse(readFileSync(dedicatedResolverPath, "utf8"));

// Extract ABIs for events
const registryEvents = l1EthRegistryDeployment.abi.filter((item: any) => item.type === "event");
const resolverEvents = dedicatedResolverDeployment.abi.filter((item: any) => item.type === "event");
const userRegistryEvents = userRegistryImplDeployment.abi.filter((item: any) => item.type === "event");

// Add type definitions for event arguments
type TransferEventArgs = {
  tokenId: bigint;
};

interface NewSubnameEventArgs {
  labelHash: string;
  label: string;
  resolver: string;
  chainId: bigint;
  subregistry: string;
  registry: string;
}

// Update event argument types
interface RegistryAddressChangedEventArgs {
  node: string;
  labelHash: string;
}

interface ResolverAddressChangedEventArgs {
  node: `0x${string}`;
  coinType: bigint;
  newAddress: string;
}

// Add these type definitions at the top with other types
type DecodedEvent = {
  eventName: string;
  args: any;
} | undefined;

// Add at the top of the file, after imports
interface ResolverInfo {
  address: string;
  addresses: Map<string, string>;
  texts: Map<string, string>;
}

// Add after the ResolverInfo interface
interface SubregistryUpdateEventArgs {
  id: bigint;
  registry: string;
  subregistry: string;
  expiry: bigint;
}

// Helper function to create registry key
function createRegistryKey(chainId: number, address: string): string {
  return `${chainId}-${address.toLowerCase()}`;
}

// Initialize maps and trees at the top
const registryTree = new Map<string, RegistryNode>();
const labelHashToLabel = new Map<string, string>();
const labelHashToSubregistry = new Map<string, string>();

// Add this function before the main event processing
async function processRegistryEvents(
  client: any,
  registryAddress: string,
  chainId: number,
  registryEvents: any[],
  processedRegistries: Set<string> = new Set()
) {
  const registryKey = createRegistryKey(chainId, registryAddress);
  if (processedRegistries.has(registryKey)) return;
  processedRegistries.add(registryKey);

  console.log(`Processing events for registry ${registryAddress} on chain ${chainId}...`);

  const logs = await client.getLogs({
    address: registryAddress as `0x${string}`,
    fromBlock: 0n,
    toBlock: await client.getBlockNumber(),
  });

  for (const log of logs) {
    const decoded = decodeEvent(log, registryEvents);
    if (!decoded || !decoded.eventName || !decoded.args) continue;
    // console.log("decoded", registryKey, decoded.eventName, decoded);
    if (decoded.eventName === "SubregistryUpdate") {
      const args = decoded.args as unknown as SubregistryUpdateEventArgs;
      const labelHash = args.id.toString();
      const subregistry = args.subregistry.toLowerCase();
      const registryKey = createRegistryKey(chainId, registryAddress);
      let registryNode = registryTree.get(registryKey);
      if (!registryNode) {
        registryNode = {
          chainId: chainId,
          expiry: Number(args.expiry),
          labels: new Map()
        };
        registryTree.set(registryKey, registryNode);
      }
      labelHashToSubregistry.set(labelHash, subregistry);
      const labelEntry = registryNode.labels.get(labelHash);
      registryNode.labels.set(labelHash, {
        label:labelEntry?.label,
        resolver: null,
        registry: subregistry,
        chainId: chainId
      });
      // Recursively process events for the subregistry
      await processRegistryEvents(client, subregistry, chainId, registryEvents, processedRegistries);
    } else if (decoded.eventName === "NewSubname") {
      const args = decoded.args as unknown as NewSubnameEventArgs;
      const labelHash = args.labelHash.toString();
      const label = args.label;
      // Update label hash to label mapping
      labelHashToLabel.set(labelHash, label);
      // Update registry node using the registry address, not the resolver
      let registryNode = registryTree.get(registryKey)
      if (!registryNode) {
        registryNode = {
          chainId: chainId,
          expiry: 0,
          labels: new Map()
        };
        // console.log("new registryNode", registryKey, registryNode);
        registryTree.set(registryKey, registryNode);
      }else{
        // console.log("existing registryNode", registryKey, registryNode);
      }
      const labelInfo = registryNode.labels.get(labelHash); 
      if (labelInfo) {
        labelInfo.label = label;
      }
      registryNode.labels.set(labelHash, labelInfo);
      registryTree.set(registryKey, registryNode);
    } else if (decoded.eventName === "ResolverUpdate") {
      const args = decoded.args as unknown as ResolverUpdateEventArgs;
      const labelHash = args.id.toString();
      const resolver = args.resolver.toLowerCase();
      const registryNode = registryTree.get(registryKey);
      if (registryNode) {
        const labelInfo = registryNode.labels.get(labelHash);
        if (labelInfo) {
          labelInfo.resolver = resolver;
          registryNode.labels.set(labelHash, labelInfo)
          registryTree.set(registryKey, registryNode);
        }
      }
    }
  }
}

// Replace the existing event processing code with calls to processRegistryEvents
console.log("Processing RootRegistry events...");
await processRegistryEvents(l1Client, rootRegistryDeployment.address, l1Chain.id, registryEvents);
console.log("RootRegistry processed", registryTree);
// Step 2: Manually insert L1 ETH Registry to L2 ETH Registry link
const l1EthRegistryKey = createRegistryKey(l1Chain.id, l1EthRegistryDeployment.address.toLowerCase());
const l2EthRegistryKey = createRegistryKey(l2Chain.id, ethRegistryDeployment.address.toLowerCase());

// Initialize L1 ETH Registry if not exists
if (!registryTree.has(l1EthRegistryKey)) {
  registryTree.set(l1EthRegistryKey, {
    chainId: l1Chain.id,
    expiry: 0,
    labels: new Map()
  });
}

// Add L2 ETH Registry link to L1 ETH Registry as a special label
const l1EthRegistry = registryTree.get(l1EthRegistryKey)!;
console.log("ethRegistryDeployment", ethRegistryDeployment.address);
l1EthRegistry.labels.set("", {
  label: "",
  resolver: null,
  chainId: l2Chain.id,
  registry: ethRegistryDeployment.address.toLowerCase()
});

// Initialize L2 ETH Registry
if (!registryTree.has(l2EthRegistryKey)) {
  registryTree.set(l2EthRegistryKey, {
    chainId: l2Chain.id,
    expiry: 0,
    labels: new Map()
  });
}
console.log("Processing L2 ETH Registry events...");
await processRegistryEvents(l2Client, ethRegistryDeployment.address, l2Chain.id, registryEvents);
// Convert registry tree to plain object for logging
const registryTreePlain = convertToPlainObject(registryTree);
console.log("Final registry tree:", JSON.stringify(registryTreePlain, null, 2));

// // Convert labelHashToLabel to plain object and log
// const labelHashToLabelPlain = Object.fromEntries(labelHashToLabel);
// console.log("\nLabel Hash to Label Mappings:", JSON.stringify(labelHashToLabelPlain, null, 2));

// // After the registry tree is built, add this debug section
// console.log("\nConstructing full names:");
// for (const [registryKey, registry] of registryTree.entries()) {
//   for (const [labelHash, labelInfo] of registry.labels.entries()) {
//     const fullName = buildFullName(registryKey, labelHash, registryTree, labelHashToLabel);
//     if (fullName) {
//       console.log(`Registry ${registryKey}: ${fullName}`);
//       console.log(`  Label: ${labelInfo.label}`);
//       console.log(`  Resolver: ${labelInfo.resolver || 'none'}`);
//       console.log(`  Registry: ${labelInfo.registry || 'none'}`);
//       if (labelInfo.subregistry) {
//         console.log(`  Subregistry: ${labelInfo.subregistry}`);
//       }
//       console.log('---');
//     }
//   }
// }

// Event types
interface ResolverUpdateEventArgs {
  registry: `0x${string}`;
  id: bigint;
  resolver: `0x${string}`;
  expiry: bigint;
  data: number;
}

interface TextChangedEventArgs {
  node: `0x${string}`;
  key: string;
  value: string;
}

type LabelHash = string;
type RegistryAddress = string;

function decodeEvent(log: Log, abi: Abi): DecodedEvent {
  try {
    return decodeEventLog({
      abi,
      data: log.data,
      topics: log.topics,
    }) as DecodedEvent;
  } catch (error) {
    return undefined;
  }
}


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

// Update RegistryNode interface to remove subregistries
interface RegistryNode {
  chainId: number;
  expiry: number;
  labels: Map<string, {
    label: string;
    resolver: string | null;
    registry: string | null;
    chainId?: number;  // Optional chainId for special labels
    subregistry?: string;  // Optional subregistry for special labels
  }>;
}

// Update collectNames function to not use subregistries
function collectNames(registryKey: string, registryTree: Map<string, RegistryNode>, labelHashToLabel: Map<string, string>, visited: Set<string> = new Set()): string[] {
  if (visited.has(registryKey)) return [];
  visited.add(registryKey);

  const registry = registryTree.get(registryKey);
  if (!registry) return [];

  const names: string[] = [];

  // Process labels in this registry
  for (const [labelHash, labelInfo] of registry.labels) {
    const label = labelHashToLabel.get(labelHash) || labelInfo.label;
    if (label) {
      const fullName = buildFullName(registryKey, labelHash, registryTree, labelHashToLabel);
      if (fullName) {
        names.push(fullName);
      }
    }
  }

  // Process special labels with subregistries
  for (const [_, labelInfo] of registry.labels) {
    if (labelInfo.subregistry) {
      const subregistryKey = createRegistryKey(labelInfo.chainId || registry.chainId, labelInfo.subregistry);
      const subNames = collectNames(subregistryKey, registryTree, labelHashToLabel, visited);
      names.push(...subNames);
    }
  }

  return names;
}

// Update printRegistryTree function to not use subregistries
function printRegistryTree(registryKey: string, registryTree: Map<string, RegistryNode>, labelHashToLabel: Map<string, string>, depth: number = 0, visited: Set<string> = new Set()) {
  if (visited.has(registryKey)) return;
  visited.add(registryKey);

  const registry = registryTree.get(registryKey);
  if (!registry) return;

  const indent = '  '.repeat(depth);
  console.log(`${indent}Registry: ${registryKey}`);
  console.log(`${indent}Chain ID: ${registry.chainId}`);

  // Print labels
  for (const [labelHash, labelInfo] of registry.labels) {
    const label = labelHashToLabel.get(labelHash) || labelInfo.label;
    if (label) {
      const fullName = buildFullName(registryKey, labelHash, registryTree, labelHashToLabel);
      console.log(`${indent}  Label: ${label} (${fullName})`);
      console.log(`${indent}    Registry: ${labelInfo.registry || 'null'}`);
      console.log(`${indent}    Resolver: ${labelInfo.resolver}`);
      if (labelInfo.subregistry) {
        console.log(`${indent}    Subregistry: ${labelInfo.subregistry}`);
        console.log(`${indent}    Chain ID: ${labelInfo.chainId}`);
      }
    }
  }

  // Process special labels with subregistries
  for (const [_, labelInfo] of registry.labels) {
    if (labelInfo.subregistry) {
      const subregistryKey = createRegistryKey(labelInfo.chainId || registry.chainId, labelInfo.subregistry);
      printRegistryTree(subregistryKey, registryTree, labelHashToLabel, depth + 1, visited);
    }
  }
}

// Function to build full name from registry tree
function buildFullName(registryKey: string, labelHash: string, registryTree: Map<string, RegistryNode>, labelHashToLabel: Map<string, string>, visited: Set<string> = new Set()): string | null {
  if (visited.has(`${registryKey}:${labelHash}`)) return null;
  visited.add(`${registryKey}:${labelHash}`);

  const registry = registryTree.get(registryKey);
  if (!registry) return null;

  const labelInfo = registry.labels.get(labelHash);
  if (!labelInfo) return null;

  const label = labelHashToLabel.get(labelHash) || labelInfo.label;
  if (!label) return null;

  // Find the parent label in any registry whose registry field matches this registry's address
  const currentRegistryAddress = registryKey.split('-')[1].toLowerCase();
  let parentLabelEntry: [string, any] | undefined;
  let parentRegistryKey: string | undefined;
  for (const [otherRegistryKey, otherRegistry] of registryTree.entries()) {
    for (const [otherLabelHash, otherLabelInfo] of otherRegistry.labels.entries()) {
      if (otherLabelInfo.registry && otherLabelInfo.registry.toLowerCase() === currentRegistryAddress) {
        parentLabelEntry = [otherLabelHash, otherLabelInfo];
        parentRegistryKey = otherRegistryKey;
        break;
      }
    }
    if (parentLabelEntry) break;
  }

  if (parentLabelEntry && parentRegistryKey) {
    const parentFullName = buildFullName(parentRegistryKey, parentLabelEntry[0], registryTree, labelHashToLabel, visited);
    if (parentFullName) {
      return `${label}.${parentFullName}`;
    }
  }

  // If this is the root (no parent), just return the label
  return label;
}

// Collect all names with their resolvers
const allNamesWithResolvers = new Map<string, { resolver: string; info: ResolverInfo }>();

// Process each registry
for (const [registryKey, registry] of registryTree.entries()) {
  for (const [labelHash, labelInfo] of registry.labels.entries()) {
    const fullName = buildFullName(registryKey, labelHash, registryTree, labelHashToLabel);
    if (fullName && labelInfo.resolver) {
      allNamesWithResolvers.set(fullName, {
        resolver: labelInfo.resolver,
        info: {
          address: labelInfo.resolver,
          addresses: new Map(),
          texts: new Map()
        }
      });
    }
  }
}

// Display all names with their resolver information
for (const [name, { resolver, info }] of allNamesWithResolvers) {
  console.log(`\nName: ${name}`);
  console.log(`  Resolver: ${resolver}`);
  
  if (info.addresses.size > 0) {
    console.log("  Addresses:");
    for (const [coinType, address] of info.addresses.entries()) {
      console.log(`    CoinType ${coinType}: ${address}`);
    }
  }
  
  if (info.texts.size > 0) {
    console.log("  Text Records:");
    for (const [key, value] of info.texts.entries()) {
      console.log(`    ${key}: ${value}`);
    }
  }
}

console.log("--------------------------------");
console.log(`Total unique names: ${allNamesWithResolvers.size}`);

// Recursively traverse from a given registry node, building full names
function traverseRegistry(
  registryKey: string,
  currentPath: string[] = [],
  names: string[] = []
): string[] {
  const registry = registryTree.get(registryKey);
  if (!registry) return names;

  for (const [labelHash, labelInfo] of registry.labels) {
    const label = labelHashToLabel.get(labelHash) || labelInfo.label;
    
    const newPath = [...currentPath, label];
    const fullName = newPath.filter((l) => l !== "").reverse().join(".");
    
    if (labelInfo.resolver) {
      names.push(fullName);
    }
    
    if (labelInfo.registry && labelInfo.registry !== "0x0000000000000000000000000000000000000000") {
      const subRegistryKey = createRegistryKey(labelInfo.chainId || registry.chainId, labelInfo.registry);
      traverseRegistry(subRegistryKey, newPath, names);
    }
  }
  
  return names;
}

// Example usage after building the registryTree:
const rootKey = createRegistryKey(l1Chain.id, rootRegistryDeployment.address.toLowerCase());
const allNames = traverseRegistry(rootKey);
console.log("All names:", allNames);

