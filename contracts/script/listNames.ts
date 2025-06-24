import { createPublicClient, http, type Chain, type Log, decodeEventLog, type Abi, PublicClient } from "viem";
import { readFileSync } from "fs";
import { join } from "path";
import { ResolverRecord, LabelInfo, RegistryNode, ResolverUpdateEventArgs, TextChangedEventArgs, AddressChangedEventArgs, SubregistryUpdateEventArgs, NewSubnameEventArgs, DecodedEvent, MetadataChangedEventArgs } from './types.js';
import { dnsDecodeName } from "../lib/ens-contracts/test/fixtures/dnsEncodeName.js";
import { deployments, eventABIs, resolverEvents } from "./shared/config.js";
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
const otherl2Chain: Chain = {
  id: 31339,
  name: "Other Local L2",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: ["http://127.0.0.1:8547"] },
    public: { http: ["http://127.0.0.1:8547"] },
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

const otherl2Client = createPublicClient({
  chain: otherl2Chain,
  transport: http(),
});

// Add at the top of the file, after imports
interface ResolverInfo {
  address: string;
  addresses: Map<string, string>;
  texts: Map<string, string>;
}

// Helper function to create registry key
function createRegistryKey(chainId: number, address: string): string {
  return `${chainId}-${address.toLowerCase()}`;
}

// Initialize maps and trees at the top
const registryTree = new Map<string, RegistryNode>();
const labelHashToLabel = new Map<string, string>();
const labelHashToSubregistry = new Map<string, string>();
const resolverRecords = new Map<string, ResolverRecord[]>();
const processedResolvers = new Set<string>();
const metadataRecords = new Map<string, MetadataChangedEventArgs>();
// Add this function before the main event processing
async function processRegistryEvents(
  client: any,
  registryAddress: string,
  chainId: number,
  registryEvents: any[],
  processedRegistries: Set<string> = new Set(),
  metadataChanged: MetadataChangedEventArgs | null = null
) {
  const registryKey = createRegistryKey(chainId, registryAddress);
  if (processedRegistries.has(registryKey)) return;
  processedRegistries.add(registryKey);

  const logs = await client.getLogs({
    address: registryAddress as `0x${string}`,
    fromBlock: 0n,
    toBlock: await client.getBlockNumber(),
  });

  for (const log of logs) {
    const decoded = decodeEvent(log, registryEvents);
    if (!decoded || !decoded.eventName || !decoded.args) continue;
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
        label: labelEntry?.label || "",
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
        registryNode.labels.set(labelHash, labelInfo);
      } else {
        // Create a new labelInfo if it doesn't exist
        registryNode.labels.set(labelHash, {
          label: label,
          resolver: null,
          registry: null,
          chainId: chainId
        });
      }
      registryTree.set(registryKey, registryNode);
    } else if (decoded.eventName === "ResolverUpdate") {
      const args = decoded.args as unknown as ResolverUpdateEventArgs;
      const labelHash = args.id.toString();
      const resolver = args.resolver.toLowerCase();
      
      // Process resolver events for the new resolver
      if (resolver && resolver !== "0x0000000000000000000000000000000000000000") {
        await processResolverEvents(client, resolver, chainId, resolverEvents, metadataChanged);
      }
      
      // Update the registry node
      const registryKey = createRegistryKey(chainId, registryAddress);
      let registryNode = registryTree.get(registryKey);
      if (!registryNode) {
        registryNode = {
          chainId,
          expiry: 0,
          labels: new Map()
        };
        registryTree.set(registryKey, registryNode);
      }
      
      const labelInfo = registryNode.labels.get(labelHash);
      if (labelInfo) {
        labelInfo.resolver = resolver;
        registryNode.labels.set(labelHash, labelInfo);
        registryTree.set(registryKey, registryNode);
      } else {
        // Create a new labelInfo if it doesn't exist
        const newLabelInfo: LabelInfo = {
          label: labelHashToLabel.get(labelHash) ?? "",
          resolver: resolver,
          registry: null,
          chainId: chainId
        };
        registryNode.labels.set(labelHash, newLabelInfo);
        registryTree.set(registryKey, registryNode);
      }
    }
  }
}


// Replace the existing event processing code with calls to processRegistryEvents
console.log("Processing RootRegistry events...");
await processRegistryEvents(l1Client, deployments.rootRegistry.address, l1Chain.id, eventABIs.registryEvents);
// Step 2: Manually insert L1 ETH Registry to L2 ETH Registry link
const l1EthRegistryKey = createRegistryKey(l1Chain.id, deployments.l1EthRegistry.address.toLowerCase());
const l2EthRegistryKey = createRegistryKey(l2Chain.id, deployments.ethRegistry.address.toLowerCase());

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

l1EthRegistry.labels.set("", {
  label: "",
  resolver: null,
  chainId: l2Chain.id,
  registry: deployments.ethRegistry.address.toLowerCase()
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
await processRegistryEvents(l2Client, deployments.ethRegistry.address, l2Chain.id, eventABIs.registryEvents);

// Convert registry tree to plain object for logging
const registryTreePlain = convertToPlainObject(registryTree);
console.log("Registry tree:", JSON.stringify(registryTreePlain, null, 2));

function decodeEvent(log: Log, abi: Abi): DecodedEvent | undefined {
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



console.log("--------------------------------");
console.log(`Total unique names: ${allNamesWithResolvers.size}`);

// Update the traverseRegistry function to look up records by resolver address
function traverseRegistry(
  registryKey: string,
  currentPath: string[] = [],
  names: Array<{ name: string; records: ResolverRecord[]; resolver: string | null }> = [],
  visited: Set<string> = new Set()
): Array<{ name: string; records: ResolverRecord[]; resolver: string | null }> {
  if (visited.has(registryKey)) {
    console.warn('Cycle detected! Registry key:', registryKey, 'Path:', currentPath.join('.'));
  }
  visited.add(registryKey);

  const registry = registryTree.get(registryKey);
  if (!registry) return names;

  for (const [labelHash, labelInfo] of registry.labels) {
    if (!labelInfo) continue;
    
    const label = labelHashToLabel.get(labelHash) ?? labelInfo.label ?? "";
    
    const newPath = [...currentPath, label];
    const fullName = newPath.filter((l) => l !== "").reverse().join(".");
    if (labelInfo.resolver) {
      names.push({
        name: fullName,
        records: resolverRecords.get(labelInfo.resolver) || [],
        resolver: labelInfo.resolver
      });
    }
    
    if (labelInfo.registry && labelInfo.registry !== "0x0000000000000000000000000000000000000000") {
      const subRegistryKey = createRegistryKey(labelInfo.chainId || 0, labelInfo.registry);
      // Need more sophisyticated logic to handle so that it won't loop forever
      if (subRegistryKey === registryKey) {
        console.warn('Warning: Registry is trying to set its own address as a subregistry:', registryKey);
      }else{
        traverseRegistry(subRegistryKey, newPath, names, visited);
      }
    }
    const metadata = metadataRecords.get(fullName)
    if(metadata){
      const subRegistryKey = createRegistryKey(parseInt(metadata.chainId), metadata.l2RegistryAddress)
      traverseRegistry(subRegistryKey, newPath, names, visited);
    }
  }
  return names;
}

// Example usage after building the registryTree:
const rootKey = createRegistryKey(l1Chain.id, deployments.rootRegistry.address.toLowerCase());
console.log('resolverRecords', resolverRecords)
console.log('metadataRecords', metadataRecords);
// Update the final output section
console.log("\nAll names with resolver records:");
const allNamesWithRecords = traverseRegistry(rootKey);
allNamesWithRecords.forEach(({ name, records, resolver }) => {
  const recordStr = records.length > 0 
    ? ` -> ${records.map(r => `${r.type}:${r.value}`).join(', ')}`
    : '';
  const resolverStr = resolver ? ` [Resolver: ${resolver}]` : ' [No resolver]';
  console.log(`${name}${resolverStr}${recordStr}`);
});

// Add resolver event tracking
async function processResolverEvents(
  client: PublicClient,
  resolverAddress: string,
  chainId: number,
  resolverEvents: any[],
  metadataChanged: MetadataChangedEventArgs | null = null
) {
  if (processedResolvers.has(resolverAddress)) return;
  processedResolvers.add(resolverAddress);
  
  const logs = await client.getLogs({
    address: resolverAddress as `0x${string}`,
    fromBlock: 0n,
    toBlock: 'latest'
  });
  console.log(`Processing resolver events for ${resolverAddress} on chain ${chainId} ${logs.length} logs`);
  let suffix
  if(metadataChanged){
    suffix = dnsDecodeName(metadataChanged.name as `0x${string}`);
  }
  for (const log of logs) {
    const decoded = decodeEvent(log, resolverEvents);
    if (!decoded || !decoded.eventName || !decoded.args) continue;

    if (["AddrChanged"].includes(decoded.eventName)) {
      const args = decoded.args as unknown as AddressChangedEventArgs;
      const records = resolverRecords.get(resolverAddress) || [];
      records.push({
        suffix,
        node: args.node,
        type: 'address',
        value: args.a || `${args.coinType}:${args.newAddress}`
      });
      resolverRecords.set(resolverAddress, records);
    } else if (decoded.eventName === "TextChanged") {
      const args = decoded.args as unknown as TextChangedEventArgs;
      const records = resolverRecords.get(resolverAddress) || [];
      records.push({
        node: args.node,
        suffix,
        type: 'text',
        value: `${args.key}=${args.value}`
      });
      resolverRecords.set(resolverAddress, records);
    }else if (decoded.eventName === "MetadataChanged") {
      const args = decoded.args as unknown as MetadataChangedEventArgs;
      const otherChainId = parseInt(args.chainId);
      if(otherChainId === otherl2Chain.id){
        processRegistryEvents(otherl2Client, args.l2RegistryAddress, otherChainId, eventABIs.registryEvents, new Set(), args);
      }
      metadataRecords.set(dnsDecodeName(args.name as `0x${string}`) , args);
    }
  }
}

