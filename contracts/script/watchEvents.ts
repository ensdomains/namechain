import { type Address, type Log, decodeEventLog, parseAbiItem } from "viem";
import { artifacts } from "@rocketh";
import fs from "fs";
import type { CrossChainEnvironment } from "./setup.js";

// ========== Types ==========

type EventLog = {
  chain: "L1" | "L2";
  registry: Address;
  registryName: string;
  eventName: string;
  blockNumber: bigint;
  logIndex: number;
  transactionHash: string;
  topics: string[];
  data: string;
  args: Record<string, any>;
  timestamp: string;
};

type RegistryInfo = {
  address: Address;
  name: string;
};

// ========== State ==========

let startBlockL1: bigint = 0n;
let startBlockL2: bigint = 0n;

// ========== Helper Functions ==========

/**
 * Convert BigInt values to strings recursively for JSON serialization
 */
function convertBigIntsToStrings(obj: any): any {
  if (obj === null || obj === undefined) {
    return obj;
  }
  if (typeof obj === "bigint") {
    return obj.toString();
  }
  if (Array.isArray(obj)) {
    return obj.map(convertBigIntsToStrings);
  }
  if (typeof obj === "object") {
    const converted: any = {};
    for (const key in obj) {
      converted[key] = convertBigIntsToStrings(obj[key]);
    }
    return converted;
  }
  return obj;
}

/**
 * Format event log for writing to file
 */
function formatEventLog(log: Log, chain: "L1" | "L2", registryName: string): EventLog {
  let eventName = "Unknown";
  let args: Record<string, any> = {};

  try {
    const decoded = decodeEventLog({
      abi: artifacts.PermissionedRegistry.abi,
      data: log.data,
      topics: log.topics,
    });
    eventName = decoded.eventName;
    args = decoded.args as any;
  } catch (e) {
    // If we can't decode, log what we can
    console.warn(`Failed to decode event from ${log.address}`);
  }

  // Convert BigInt values to strings for JSON serialization
  return convertBigIntsToStrings({
    chain,
    registry: log.address,
    registryName,
    eventName,
    blockNumber: log.blockNumber || 0n,
    logIndex: log.logIndex || 0,
    transactionHash: log.transactionHash || "",
    topics: log.topics,
    data: log.data,
    args,
    timestamp: new Date().toISOString(),
  });
}

/**
 * Write events to log file
 */
function writeEventsToFile(events: EventLog[], logFile: string) {
  for (const event of events) {
    const logLine = JSON.stringify(event) + "\n";
    fs.appendFileSync(logFile, logLine);
  }
}

/**
 * Discover all subregistries by recursively querying SubregistryUpdate events
 */
async function discoverAllSubregistries(
  client: any,
  registryAddress: Address,
  fromBlock: bigint,
  toBlock: bigint | "latest",
  parentName?: string,
): Promise<RegistryInfo[]> {
  const registries: RegistryInfo[] = [];
  const registryName = parentName || "ETHRegistry (root)";

  // Add this registry
  registries.push({ address: registryAddress, name: registryName });

  try {
    // Query SubregistryUpdate events
    const logs = await client.getLogs({
      address: registryAddress,
      event: parseAbiItem("event SubregistryUpdate(uint256 indexed id, address subregistry)"),
      fromBlock,
      toBlock,
    });

    // For each subregistry discovered, recursively find its subregistries
    for (const log of logs) {
      const { subregistry } = log.args as { id: bigint; subregistry: Address };

      if (subregistry === "0x0000000000000000000000000000000000000000") {
        continue;
      }

      // Use generic name since we can't easily get the label
      const subName = parentName ? `<sub>.${parentName}` : `<sub>.eth`;

      // Recursively discover nested subregistries
      const nestedRegistries = await discoverAllSubregistries(
        client,
        subregistry,
        fromBlock,
        toBlock,
        subName,
      );

      registries.push(...nestedRegistries);
    }
  } catch (e) {
    console.warn(`Warning: Failed to query SubregistryUpdate for ${registryAddress}`);
  }

  return registries;
}

/**
 * Collect all events from a registry
 */
async function collectRegistryEvents(
  client: any,
  registry: RegistryInfo,
  fromBlock: bigint,
  toBlock: bigint | "latest",
  chain: "L1" | "L2",
): Promise<EventLog[]> {
  const events: EventLog[] = [];

  try {
    const logs = await client.getLogs({
      address: registry.address,
      fromBlock,
      toBlock,
    });

    for (const log of logs) {
      const eventLog = formatEventLog(log, chain, registry.name);
      events.push(eventLog);
    }
  } catch (e) {
    console.warn(`Warning: Failed to collect events for ${registry.address}`);
  }

  return events;
}

/**
 * Deduplicate registries by address, keeping the first occurrence (shortest path)
 */
function deduplicateRegistries(registries: RegistryInfo[]): RegistryInfo[] {
  const seen = new Set<string>();
  const deduplicated: RegistryInfo[] = [];

  for (const registry of registries) {
    const addressLower = registry.address.toLowerCase();
    if (!seen.has(addressLower)) {
      seen.add(addressLower);
      deduplicated.push(registry);
    }
  }

  return deduplicated;
}

// ========== Public API ==========

/**
 * Initialize event logging - starts from genesis to capture deployment events
 */
export async function initializeEventLogging(env: CrossChainEnvironment) {
  console.log("\n========== Initializing Event Logging ==========\n");

  // Start from block 0 to capture deployment events (including "eth" TLD registration on RootRegistry)
  startBlockL1 = 0n;
  startBlockL2 = 0n;

  console.log(`L1 starting block: ${startBlockL1} (from genesis)`);
  console.log(`L2 starting block: ${startBlockL2} (from genesis)`);

  // Ensure tmp directory exists
  if (!fs.existsSync("tmp")) {
    fs.mkdirSync("tmp");
  }

  // Clear previous logs
  fs.writeFileSync("tmp/l1-local-events.log", "");
  fs.writeFileSync("tmp/l2-local-events.log", "");

  console.log("Event logging initialized. Events will be collected at the end.\n");
}

/**
 * Collect all events from registries and write to log files
 */
export async function collectAndWriteEvents(env: CrossChainEnvironment) {
  console.log("\n========== Collecting Registry Events ==========\n");

  const endBlockL1 = await env.l1.client.getBlockNumber();
  const endBlockL2 = await env.l2.client.getBlockNumber();

  console.log(`L1 block range: ${startBlockL1} → ${endBlockL1}`);
  console.log(`L2 block range: ${startBlockL2} → ${endBlockL2}\n`);

  // Discover all registries on L1 (both RootRegistry and ETHRegistry hierarchies)
  console.log("🔍 Discovering L1 registries...");
  const l1RootRegistries = await discoverAllSubregistries(
    env.l1.client,
    env.l1.contracts.RootRegistry.address,
    startBlockL1,
    endBlockL1,
    "RootRegistry",
  );
  const l1EthRegistries = await discoverAllSubregistries(
    env.l1.client,
    env.l1.contracts.ETHRegistry.address,
    startBlockL1,
    endBlockL1,
    "ETHRegistry (.eth)",
  );
  const l1RegistriesRaw = [...l1RootRegistries, ...l1EthRegistries];
  const l1Registries = deduplicateRegistries(l1RegistriesRaw);
  console.log(`Found ${l1Registries.length} unique L1 registries (${l1RegistriesRaw.length} total discovered, ${l1RootRegistries.length} from Root, ${l1EthRegistries.length} from ETH)\n`);

  // Discover all registries on L2
  console.log("🔍 Discovering L2 registries...");
  const l2RegistriesRaw = await discoverAllSubregistries(
    env.l2.client,
    env.l2.contracts.ETHRegistry.address,
    startBlockL2,
    endBlockL2,
  );
  const l2Registries = deduplicateRegistries(l2RegistriesRaw);
  console.log(`Found ${l2Registries.length} unique L2 registries (${l2RegistriesRaw.length} total discovered)\n`);

  // Collect L1 events
  console.log("📝 Collecting L1 events...");
  let allL1Events: EventLog[] = [];
  for (const registry of l1Registries) {
    const events = await collectRegistryEvents(
      env.l1.client,
      registry,
      startBlockL1,
      endBlockL1,
      "L1",
    );
    allL1Events.push(...events);
  }
  console.log(`Collected ${allL1Events.length} L1 events\n`);

  // Collect L2 events
  console.log("📝 Collecting L2 events...");
  let allL2Events: EventLog[] = [];
  for (const registry of l2Registries) {
    const events = await collectRegistryEvents(
      env.l2.client,
      registry,
      startBlockL2,
      endBlockL2,
      "L2",
    );
    allL2Events.push(...events);
  }
  console.log(`Collected ${allL2Events.length} L2 events\n`);

  // Write to files
  console.log("💾 Writing events to log files...");
  writeEventsToFile(allL1Events, "tmp/l1-local-events.log");
  writeEventsToFile(allL2Events, "tmp/l2-local-events.log");

  console.log("✓ Event logs written to:");
  console.log("  - tmp/l1-local-events.log");
  console.log("  - tmp/l2-local-events.log\n");
}

/**
 * Stop event logging (no-op for historical approach)
 */
export function stopEventLogging() {
  // No-op since we're not watching in real-time
}

/**
 * Display summary of logged events
 */
export function displayEventSummary() {
  console.log("\n========== Event Logging Summary ==========\n");

  try {
    const l1Events = fs
      .readFileSync("tmp/l1-local-events.log", "utf-8")
      .split("\n")
      .filter((line) => line.trim().length > 0);

    const l2Events = fs
      .readFileSync("tmp/l2-local-events.log", "utf-8")
      .split("\n")
      .filter((line) => line.trim().length > 0);

    console.log(`L1 Events Logged: ${l1Events.length}`);
    console.log(`L2 Events Logged: ${l2Events.length}`);

    // Count by event type
    const l1EventCounts = new Map<string, number>();
    const l2EventCounts = new Map<string, number>();

    for (const line of l1Events) {
      try {
        const event = JSON.parse(line) as EventLog;
        l1EventCounts.set(event.eventName, (l1EventCounts.get(event.eventName) || 0) + 1);
      } catch (e) {
        // Skip invalid JSON
      }
    }

    for (const line of l2Events) {
      try {
        const event = JSON.parse(line) as EventLog;
        l2EventCounts.set(event.eventName, (l2EventCounts.get(event.eventName) || 0) + 1);
      } catch (e) {
        // Skip invalid JSON
      }
    }

    if (l1EventCounts.size > 0) {
      console.log("\nL1 Event Breakdown:");
      for (const [eventName, count] of l1EventCounts) {
        console.log(`  ${eventName}: ${count}`);
      }
    }

    if (l2EventCounts.size > 0) {
      console.log("\nL2 Event Breakdown:");
      for (const [eventName, count] of l2EventCounts) {
        console.log(`  ${eventName}: ${count}`);
      }
    }

    console.log("\n==========================================\n");
  } catch (e) {
    console.log("No event logs found or error reading logs.\n");
  }
}
