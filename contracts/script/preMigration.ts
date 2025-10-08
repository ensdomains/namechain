#!/usr/bin/env bun

import { artifacts } from "@rocketh";
import { Command } from "commander";
import { writeFileSync, existsSync, readFileSync, rmSync } from "node:fs";
import {
  createWalletClient,
  http,
  type Address,
  type Hash,
  zeroAddress,
  getContract,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import {
  Logger,
  red,
  green,
  yellow,
  blue,
  cyan,
  magenta,
  bold,
  dim,
} from "./logger.js";
import { ROLES } from "../deploy/constants.js";

// Custom Errors
export class UnexpectedOwnerError extends Error {
  constructor(
    public readonly labelName: string,
    public readonly actualOwner: Address,
    public readonly expectedOwner: Address
  ) {
    super(
      `Name ${labelName}.eth is already registered but owned by unexpected address: ${actualOwner} (expected: ${expectedOwner})`
    );
    this.name = "UnexpectedOwnerError";
  }
}

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
  fresh?: boolean;
  disableCheckpoint?: boolean;
}

interface Checkpoint {
  lastProcessedIndex: number;
  totalProcessed: number;
  successCount: number;
  failureCount: number;
  skippedCount: number;
  timestamp: string;
}

interface RegistrationResult {
  labelName: string;
  success: boolean;
  txHash?: Hash;
  error?: string;
  skipped?: boolean;
}

// Constants
// ENS Subgraph ID (mainnet) - https://thegraph.com/explorer/subgraphs/5XqPmWe6gjyrJtFn9cLy237i4cWw2j9HcUJEXsP5qGtH
const SUBGRAPH_ID = "5XqPmWe6gjyrJtFn9cLy237i4cWw2j9HcUJEXsP5qGtH";
const GATEWAY_ENDPOINT = `https://gateway.thegraph.com/api/{API_KEY}/subgraphs/id/${SUBGRAPH_ID}`;

const CHECKPOINT_FILE = "preMigration-checkpoint.json";
const ERROR_LOG_FILE = "preMigration-errors.log";
const INFO_LOG_FILE = "preMigration.log";
const MAX_RETRIES = 3;

// Cleanup utilities
function cleanupPreviousRun(): void {
  const files = [CHECKPOINT_FILE, ERROR_LOG_FILE, INFO_LOG_FILE];

  for (const file of files) {
    try {
      if (existsSync(file)) {
        rmSync(file);
        logger.cleanup(file, true);
      }
    } catch (error) {
      logger.cleanup(file, false);
    }
  }
}

// Pre-migration specific logger
class PreMigrationLogger extends Logger {
  constructor() {
    super({
      infoLogFile: INFO_LOG_FILE,
      errorLogFile: ERROR_LOG_FILE,
      enableFileLogging: true,
    });
  }

  registering(name: string, expiry: string): void {
    this.raw(
      blue(`Registering: ${bold(name)}.eth`) + dim(` (expires: ${expiry})`),
      `Registering: ${name}.eth (expires: ${expiry})`
    );
  }

  registered(name: string, tx: string): void {
    this.raw(
      green(`  → ✓ Registered successfully`) + dim(` (tx: ${tx})`),
      `  → ✓ Registered successfully (tx: ${tx})`
    );
  }

  skipped(name: string, owner: string): void {
    this.raw(
      yellow(`Skipping: ${bold(name)}.eth`),
      `Skipping: ${name}.eth`
    );
    this.raw(
      yellow(`  → ⊘ Already registered by this migration`) +
        dim(` (owner: ${owner}...)`),
      `  → ⊘ Already registered by this migration (owner: ${owner}...)`
    );
  }

  failed(
    name: string,
    error: string,
    attempt?: number,
    maxRetries?: number
  ): void {
    const attemptInfo = attempt
      ? ` (attempt ${attempt}/${maxRetries})`
      : ` after ${maxRetries} attempts`;
    this.rawError(
      red(`  → ✗ Failed${attemptInfo}:`) + dim(` ${error}`),
      `  → ✗ Failed${attemptInfo}: ${error}`
    );
  }

  dryRun(): void {
    this.raw(
      dim(`  → [DRY RUN] Simulated registration (no transaction sent)`),
      `  → [DRY RUN] Simulated registration (no transaction sent)`
    );
  }

  progress(
    current: number,
    total: number,
    stats: { registered: number; skipped: number; failed: number }
  ): void {
    const percent = Math.round((current / total) * 100);
    this.raw(
      magenta(
        `Progress: ${bold(`${current}/${total}`)} (${percent}%) - ` +
          `${green("Registered: " + stats.registered)}, ` +
          `${yellow("Skipped: " + stats.skipped)}, ` +
          `${red("Failed: " + stats.failed)}`
      ),
      `Progress: ${current}/${total} (${percent}%) - Registered: ${stats.registered}, Skipped: ${stats.skipped}, Failed: ${stats.failed}`
    );
  }
}

const logger = new PreMigrationLogger();

// Checkpoint management
function loadCheckpoint(): Checkpoint | null {
  if (!existsSync(CHECKPOINT_FILE)) {
    return null;
  }

  try {
    const data = readFileSync(CHECKPOINT_FILE, "utf-8");
    return JSON.parse(data);
  } catch (error) {
    logger.error(`Failed to load checkpoint: ${error}`);
    return null;
  }
}

function saveCheckpoint(checkpoint: Checkpoint): void {
  try {
    writeFileSync(CHECKPOINT_FILE, JSON.stringify(checkpoint, null, 2));
  } catch (error) {
    logger.error(`Failed to save checkpoint: ${error}`);
  }
}

// TheGraph queries
async function fetchRegistrations(
  config: PreMigrationConfig,
  skip: number,
  first: number
): Promise<ENSRegistration[]> {
  const endpoint = GATEWAY_ENDPOINT.replace("{API_KEY}", config.thegraphApiKey);

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
    const errorText = await response.text();
    throw new Error(`HTTP error! status: ${response.status}, body: ${errorText}`);
  }

  const result: GraphQLResponse = await response.json();

  // Debug: Log the actual response structure
  if (!result.data || !result.data.registrations) {
    logger.error(`Unexpected TheGraph response structure: ${JSON.stringify(result, null, 2)}`);
  }

  if (result.errors) {
    throw new Error(
      `GraphQL error: ${result.errors.map((e) => e.message).join(", ")}`
    );
  }

  if (!result.data || !result.data.registrations) {
    throw new Error(`Invalid response structure from TheGraph: missing data.registrations`);
  }

  return result.data.registrations;
}

export async function fetchAllRegistrations(
  config: PreMigrationConfig
): Promise<ENSRegistration[]> {
  const allRegistrations: ENSRegistration[] = [];
  let skip = config.startIndex;
  let hasMore = true;

  logger.info(`Fetching registrations from TheGraph Gateway...`);

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

      logger.info(
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
      logger.error(`Failed to fetch registrations at skip=${skip}: ${error}`);
      throw error;
    }
  }

  logger.info(`Total registrations fetched: ${allRegistrations.length}`);
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
    // Check if name is already registered
    try {
      const [tokenId] = await registry.read.getNameData([labelName]);
      const owner = await registry.read.ownerOf([tokenId]);

      if (owner !== zeroAddress) {
        // Verify the owner is the bridge controller (from this migration)
        if (owner.toLowerCase() !== config.bridgeControllerAddress.toLowerCase()) {
          logger.error(`Name ${labelName}.eth is already registered but owned by unexpected address: ${owner}`);
          throw new UnexpectedOwnerError(labelName, owner, config.bridgeControllerAddress);
        }

        logger.skipped(labelName, owner.substring(0, 10));
        return { labelName, success: true, skipped: true };
      }
    } catch (error) {
      // If it's our validation error, re-throw it
      if (error instanceof UnexpectedOwnerError) {
        throw error;
      }
      // Otherwise, name doesn't exist or error checking - proceed with registration
    }

    // Convert expiry to uint64
    const expires = BigInt(expiryDate);
    const expiryDateFormatted = new Date(Number(expiryDate) * 1000).toISOString().split('T')[0];

    logger.registering(labelName, expiryDateFormatted);

    if (config.dryRun) {
      logger.dryRun();
      return { labelName, success: true };
    }

    const hash = await registry.write.register([
      labelName,
      config.bridgeControllerAddress,
      zeroAddress, // No subregistry for pre-migration
      zeroAddress, // No resolver initially
      config.roleBitmap,
      expires,
    ]);

    await client.waitForTransactionReceipt({ hash });

    logger.registered(labelName, hash);
    return { labelName, success: true, txHash: hash };
  } catch (error) {
    // Re-throw validation errors (name owned by unexpected address) - don't retry
    if (error instanceof UnexpectedOwnerError) {
      throw error;
    }

    const errorMessage = error instanceof Error ? error.message : String(error);

    if (retries < MAX_RETRIES) {
      logger.failed(labelName, errorMessage, retries + 1, MAX_RETRIES);
      await new Promise((resolve) => setTimeout(resolve, 1000 * (retries + 1)));
      return registerName(client, registry, config, registration, retries + 1);
    }

    logger.failed(labelName, errorMessage, undefined, MAX_RETRIES);
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

  logger.info(`\nStarting registration process...`);
  logger.info(`Total names to register: ${registrations.length}`);
  logger.info(`Batch size: ${config.batchSize}`);
  logger.info(`Dry run: ${config.dryRun}`);

  // Load checkpoint (unless disabled for testing)
  let checkpoint: Checkpoint;
  if (config.disableCheckpoint) {
    checkpoint = {
      lastProcessedIndex: -1,
      totalProcessed: 0,
      successCount: 0,
      failureCount: 0,
      skippedCount: 0,
      timestamp: new Date().toISOString(),
    };
  } else {
    const loaded = loadCheckpoint();
    checkpoint = loaded || {
      lastProcessedIndex: -1,
      totalProcessed: 0,
      successCount: 0,
      failureCount: 0,
      skippedCount: 0,
      timestamp: new Date().toISOString(),
    };
    // Handle legacy checkpoints without skippedCount
    if (loaded && !('skippedCount' in loaded)) {
      checkpoint.skippedCount = 0;
    }
  }

  const results: RegistrationResult[] = [];
  const startIndex = checkpoint.lastProcessedIndex + 1;

  for (let i = startIndex; i < registrations.length; i++) {
    const registration = registrations[i];
    const result = await registerName(client, registry, config, registration);
    results.push(result);

    if (result.skipped) {
      checkpoint.skippedCount++;
      // Don't increment totalProcessed for skipped names
    } else if (result.success) {
      checkpoint.successCount++;
      checkpoint.totalProcessed++;
    } else {
      checkpoint.failureCount++;
      checkpoint.totalProcessed++;
    }

    checkpoint.lastProcessedIndex = i;
    checkpoint.timestamp = new Date().toISOString();

    // Save checkpoint periodically (unless disabled)
    // Use total attempted (not just processed) for progress
    const totalAttempted = checkpoint.successCount + checkpoint.failureCount + checkpoint.skippedCount;
    if (!config.disableCheckpoint && totalAttempted % 10 === 0) {
      saveCheckpoint(checkpoint);
      logger.progress(totalAttempted, registrations.length, {
        registered: checkpoint.successCount,
        skipped: checkpoint.skippedCount,
        failed: checkpoint.failureCount,
      });
    }
  }

  // Final checkpoint save (unless disabled)
  if (!config.disableCheckpoint) {
    saveCheckpoint(checkpoint);
  }

  // Summary
  const totalAttempted = checkpoint.successCount + checkpoint.failureCount + checkpoint.skippedCount;
  const actualRegistrations = checkpoint.successCount + checkpoint.failureCount;

  logger.info('');
  logger.divider();
  logger.header('Pre-Migration Complete');
  logger.divider();

  logger.config('Total names checked', totalAttempted);
  logger.config('Successfully registered', green(checkpoint.successCount.toString()));
  logger.config('Skipped (already registered)', yellow(checkpoint.skippedCount.toString()));
  logger.config('Failed', checkpoint.failureCount > 0 ? red(checkpoint.failureCount.toString()) : checkpoint.failureCount);
  logger.config('Actual registrations attempted', checkpoint.totalProcessed);

  if (actualRegistrations > 0) {
    const rate = Math.round((checkpoint.successCount / actualRegistrations) * 100);
    logger.config('Registration success rate', `${rate}%`);
  }

  logger.divider();

  if (checkpoint.failureCount > 0) {
    logger.warning(`\nSome registrations failed. Check ${ERROR_LOG_FILE} for details.`);
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
    .requiredOption("--thegraph-api-key <key>", "TheGraph Gateway API key (get from https://thegraph.com/studio/apikeys/)")
    .option("--batch-size <number>", "Number of names to fetch per TheGraph API request", "100")
    .option("--start-index <number>", "Starting index for resuming partial migrations", "0")
    .option("--limit <number>", "Maximum total number of names to fetch and register")
    .option("--dry-run", "Simulate without executing transactions", false)
    .option("--fresh", "Delete previous logs and checkpoints before starting", false)
    .option("--role-bitmap <hex>", "Custom role bitmap (hex string) for when registering names");

  program.parse(argv);
  const opts = program.opts();

  const config: PreMigrationConfig = {
    rpcUrl: opts.rpcUrl,
    registryAddress: opts.registry as Address,
    bridgeControllerAddress: opts.bridgeController as Address,
    privateKey: opts.privateKey as `0x${string}`,
    thegraphApiKey: opts.thegraphApiKey,
    batchSize: parseInt(opts.batchSize) || 100,
    startIndex: parseInt(opts.startIndex) || 0,
    limit: opts.limit ? parseInt(opts.limit) : null,
    dryRun: opts.dryRun,
    fresh: opts.fresh,
    roleBitmap: opts.roleBitmap ? BigInt(opts.roleBitmap) : ROLES.ALL,
  };

  try {
    // Clean up previous run if --fresh flag is set
    if (config.fresh) {
      console.log("\nCleaning up previous migration files...");
      cleanupPreviousRun();
      console.log("");
    }

    logger.header("ENS Pre-Migration Script");
    logger.divider();

    logger.info(`Configuration:`);
    logger.config('RPC URL', config.rpcUrl);
    logger.config('Registry', config.registryAddress);
    logger.config('Bridge Controller', config.bridgeControllerAddress);
    logger.config('TheGraph API Key', `${config.thegraphApiKey.substring(0, 8)}...`);
    logger.config('Batch Size', config.batchSize);
    logger.config('Start Index', config.startIndex);
    logger.config('Limit', config.limit ?? "none");
    logger.config('Dry Run', config.dryRun);
    logger.config('Fresh Start', config.fresh ?? false);
    logger.config('Role Bitmap', `0x${config.roleBitmap.toString(16)}`);
    logger.info("");

    // Fetch registrations from TheGraph
    const registrations = await fetchAllRegistrations(config);

    if (registrations.length === 0) {
      logger.warning("No registrations found. Exiting.");
      return;
    }

    // Register names on L2
    await batchRegisterNames(config, registrations);

    logger.success("\nPre-migration script completed successfully!");
  } catch (error) {
    logger.error(`Fatal error: ${error}`);
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
