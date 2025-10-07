#!/usr/bin/env bun

import { artifacts } from "@rocketh";
import { Command } from "commander";
import { writeFileSync, existsSync, readFileSync } from "node:fs";
import {
  createWalletClient,
  http,
  type Address,
  type Hash,
  zeroAddress,
  getContract,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { ROLES } from "../deploy/constants.js";

// Types
export interface ENSRegistration {
  id: string;
  labelName: string;
  registrant: string;
  expiryDate: string;
  registrationDate: string;
  domain: {
    name: string;
    labelhash: string;
    parent: {
      id: string;
    };
  };
}

interface GraphQLResponse {
  data: {
    registrations: ENSRegistration[];
  };
  errors?: Array<{ message: string }>;
}

export interface PreMigrationConfig {
  rpcUrl: string;
  registryAddress: Address;
  bridgeControllerAddress: Address;
  privateKey: `0x${string}`;
  thegraphApiKey: string;
  batchSize: number;
  startIndex: number;
  limit: number | null;
  dryRun: boolean;
  roleBitmap: bigint;
  disableCheckpoint?: boolean;
}

interface Checkpoint {
  lastProcessedIndex: number;
  totalProcessed: number;
  successCount: number;
  failureCount: number;
  timestamp: string;
}

interface RegistrationResult {
  labelName: string;
  success: boolean;
  txHash?: Hash;
  error?: string;
}

// Constants
const SUBGRAPH_ENDPOINT =
  "https://gateway.thegraph.com/api/{API_KEY}/subgraphs/id/QmcqvocMfm9LDSEDYmeexzeGt1QTY7T7AVitX9mG2qkvjR";

const CHECKPOINT_FILE = "preMigration-checkpoint.json";
const ERROR_LOG_FILE = "preMigration-errors.log";
const INFO_LOG_FILE = "preMigration.log";
const MAX_RETRIES = 3;

// Logging utilities
function log(message: string): void {
  const timestamp = new Date().toISOString();
  const logMessage = `[${timestamp}] ${message}\n`;
  console.log(message);
  writeFileSync(INFO_LOG_FILE, logMessage, { flag: "a" });
}

function logError(message: string): void {
  const timestamp = new Date().toISOString();
  const errorMessage = `[${timestamp}] ERROR: ${message}\n`;
  console.error(`ERROR: ${message}`);
  writeFileSync(ERROR_LOG_FILE, errorMessage, { flag: "a" });
}

// Checkpoint management
function loadCheckpoint(): Checkpoint | null {
  if (!existsSync(CHECKPOINT_FILE)) {
    return null;
  }

  try {
    const data = readFileSync(CHECKPOINT_FILE, "utf-8");
    return JSON.parse(data);
  } catch (error) {
    logError(`Failed to load checkpoint: ${error}`);
    return null;
  }
}

function saveCheckpoint(checkpoint: Checkpoint): void {
  try {
    writeFileSync(CHECKPOINT_FILE, JSON.stringify(checkpoint, null, 2));
  } catch (error) {
    logError(`Failed to save checkpoint: ${error}`);
  }
}

// TheGraph queries
async function fetchRegistrations(
  config: PreMigrationConfig,
  skip: number,
  first: number
): Promise<ENSRegistration[]> {
  const endpoint = SUBGRAPH_ENDPOINT.replace(
    "{API_KEY}",
    config.thegraphApiKey
  );

  const query = `
    query GetEthRegistrations($first: Int!, $skip: Int!) {
      registrations(
        first: $first
        skip: $skip
        orderBy: registrationDate
        orderDirection: asc
      ) {
        id
        labelName
        registrant
        expiryDate
        registrationDate
        domain {
          name
          labelhash
          parent {
            id
          }
        }
      }
    }
  `;

  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      query,
      variables: { first, skip },
    }),
  });

  if (!response.ok) {
    throw new Error(`HTTP error! status: ${response.status}`);
  }

  const result: GraphQLResponse = await response.json();

  if (result.errors) {
    throw new Error(
      `GraphQL error: ${result.errors.map((e) => e.message).join(", ")}`
    );
  }

  return result.data.registrations;
}

export async function fetchAllRegistrations(
  config: PreMigrationConfig
): Promise<ENSRegistration[]> {
  const allRegistrations: ENSRegistration[] = [];
  let skip = config.startIndex;
  let hasMore = true;

  log("Fetching registrations from TheGraph...");

  while (hasMore) {
    try {
      const registrations = await fetchRegistrations(
        config,
        skip,
        config.batchSize
      );

      if (registrations.length === 0) {
        hasMore = false;
        break;
      }

      allRegistrations.push(...registrations);
      skip += registrations.length;

      log(
        `Fetched ${registrations.length} registrations (total: ${allRegistrations.length})`
      );

      // Check limit
      if (config.limit && allRegistrations.length >= config.limit) {
        allRegistrations.splice(config.limit);
        hasMore = false;
        break;
      }

      // Rate limiting
      await new Promise((resolve) => setTimeout(resolve, 200));
    } catch (error) {
      logError(`Failed to fetch registrations at skip=${skip}: ${error}`);
      throw error;
    }
  }

  log(`Total registrations fetched: ${allRegistrations.length}`);
  return allRegistrations;
}

// Registration logic
async function registerName(
  client: any,
  registry: any,
  config: PreMigrationConfig,
  registration: ENSRegistration,
  retries = 0
): Promise<RegistrationResult> {
  const { labelName, expiryDate } = registration;

  try {
    if (config.dryRun) {
      log(`[DRY RUN] Would register: ${labelName}.eth`);
      return { labelName, success: true };
    }

    // Convert expiry to uint64
    const expires = BigInt(expiryDate);

    log(`Registering: ${labelName}.eth (expires: ${expiryDate})`);

    const hash = await registry.write.register([
      labelName,
      config.bridgeControllerAddress,
      zeroAddress, // No subregistry for pre-migration
      zeroAddress, // No resolver initially
      config.roleBitmap,
      expires,
    ]);

    await client.waitForTransactionReceipt({ hash });

    log(`✓ Registered: ${labelName}.eth (tx: ${hash})`);
    return { labelName, success: true, txHash: hash };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);

    if (retries < MAX_RETRIES) {
      logError(
        `Failed to register ${labelName}.eth (attempt ${retries + 1}/${MAX_RETRIES}): ${errorMessage}`
      );
      await new Promise((resolve) => setTimeout(resolve, 1000 * (retries + 1)));
      return registerName(client, registry, config, registration, retries + 1);
    }

    logError(`Failed to register ${labelName}.eth after ${MAX_RETRIES} attempts: ${errorMessage}`);
    return { labelName, success: false, error: errorMessage };
  }
}

export async function batchRegisterNames(
  config: PreMigrationConfig,
  registrations: ENSRegistration[],
  providedClient?: any,
  providedRegistry?: any
): Promise<void> {
  const client = providedClient || createWalletClient({
    account: privateKeyToAccount(config.privateKey),
    transport: http(config.rpcUrl, {
      retryCount: 0,
      timeout: 30000,
    }),
  });

  const registry = providedRegistry || getContract({
    address: config.registryAddress,
    abi: artifacts.PermissionedRegistry.abi,
    client,
  });

  log(`\nStarting registration process...`);
  log(`Total names to register: ${registrations.length}`);
  log(`Batch size: ${config.batchSize}`);
  log(`Dry run: ${config.dryRun}`);

  // Load checkpoint (unless disabled for testing)
  let checkpoint: Checkpoint;
  if (config.disableCheckpoint) {
    checkpoint = {
      lastProcessedIndex: -1,
      totalProcessed: 0,
      successCount: 0,
      failureCount: 0,
      timestamp: new Date().toISOString(),
    };
  } else {
    checkpoint = loadCheckpoint() || {
      lastProcessedIndex: -1,
      totalProcessed: 0,
      successCount: 0,
      failureCount: 0,
      timestamp: new Date().toISOString(),
    };
  }

  const results: RegistrationResult[] = [];
  const startIndex = checkpoint.lastProcessedIndex + 1;

  for (let i = startIndex; i < registrations.length; i++) {
    const registration = registrations[i];
    const result = await registerName(client, registry, config, registration);
    results.push(result);

    if (result.success) {
      checkpoint.successCount++;
    } else {
      checkpoint.failureCount++;
    }

    checkpoint.totalProcessed++;
    checkpoint.lastProcessedIndex = i;
    checkpoint.timestamp = new Date().toISOString();

    // Save checkpoint periodically (unless disabled)
    if (!config.disableCheckpoint && checkpoint.totalProcessed % 10 === 0) {
      saveCheckpoint(checkpoint);
      log(
        `Progress: ${checkpoint.totalProcessed}/${registrations.length} (${Math.round((checkpoint.totalProcessed / registrations.length) * 100)}%)`
      );
    }
  }

  // Final checkpoint save (unless disabled)
  if (!config.disableCheckpoint) {
    saveCheckpoint(checkpoint);
  }

  // Summary
  log(`\n${"=".repeat(60)}`);
  log(`Pre-Migration Complete`);
  log(`${"=".repeat(60)}`);
  log(`Total processed: ${checkpoint.totalProcessed}`);
  log(`Successful: ${checkpoint.successCount}`);
  log(`Failed: ${checkpoint.failureCount}`);
  log(`Success rate: ${Math.round((checkpoint.successCount / checkpoint.totalProcessed) * 100)}%`);
  log(`${"=".repeat(60)}`);

  if (checkpoint.failureCount > 0) {
    log(`\nSome registrations failed. Check ${ERROR_LOG_FILE} for details.`);
  }
}

// Main function - exported for testing
export async function main(argv = process.argv): Promise<void> {
  const program = new Command()
    .name("premigrate")
    .description("Pre-migrate ENS .eth 2LDs from Mainnet to v2")
    .requiredOption("--rpc-url <url>", "v2 chain RPC endpoint")
    .requiredOption("--registry <address>", "ETH Registry contract address")
    .requiredOption("--bridge-controller <address>", "L2BridgeController address")
    .requiredOption("--private-key <key>", "Deployer private key (has REGISTRAR role)")
    .requiredOption("--thegraph-api-key <key>", "TheGraph API key for subgraph access")
    .option("--batch-size <number>", "Number of names to fetch per TheGraph API request", parseInt, 100)
    .option("--start-index <number>", "Starting index for resuming partial migrations", parseInt, 0)
    .option("--limit <number>", "Maximum total number of names to fetch and register", parseInt)
    .option("--dry-run", "Simulate without executing transactions", false)
    .option("--role-bitmap <hex>", "Custom role bitmap (hex string) for when registering names");

  program.parse(argv);
  const opts = program.opts();

  const config: PreMigrationConfig = {
    rpcUrl: opts.rpcUrl,
    registryAddress: opts.registry as Address,
    bridgeControllerAddress: opts.bridgeController as Address,
    privateKey: opts.privateKey as `0x${string}`,
    thegraphApiKey: opts.thegraphApiKey,
    batchSize: opts.batchSize,
    startIndex: opts.startIndex,
    limit: opts.limit ?? null,
    dryRun: opts.dryRun,
    roleBitmap: opts.roleBitmap ? BigInt(opts.roleBitmap) : ROLES.ALL,
  };

  try {
    log("ENS Pre-Migration Script");
    log("=".repeat(60));

    log(`Configuration:`);
    log(`  RPC URL: ${config.rpcUrl}`);
    log(`  Registry: ${config.registryAddress}`);
    log(`  Bridge Controller: ${config.bridgeControllerAddress}`);
    log(`  Batch Size: ${config.batchSize}`);
    log(`  Start Index: ${config.startIndex}`);
    log(`  Limit: ${config.limit ?? "none"}`);
    log(`  Dry Run: ${config.dryRun}`);
    log(`  Role Bitmap: 0x${config.roleBitmap.toString(16)}`);
    log("");

    // Fetch registrations from TheGraph
    const registrations = await fetchAllRegistrations(config);

    if (registrations.length === 0) {
      log("No registrations found. Exiting.");
      return;
    }

    // Register names on L2
    await batchRegisterNames(config, registrations);

    log("\nPre-migration script completed successfully!");
  } catch (error) {
    logError(`Fatal error: ${error}`);
    console.error(error);
    process.exit(1);
  }
}

// CLI entry point
if (import.meta.main) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
