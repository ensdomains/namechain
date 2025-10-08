#!/usr/bin/env bun

import { artifacts } from "@rocketh";
import { Command } from "commander";
import { writeFileSync, existsSync, readFileSync, rmSync } from "node:fs";
import {
  createWalletClient,
  createPublicClient,
  http,
  type Address,
  type Hash,
  zeroAddress,
  getContract,
  keccak256,
  toHex,
  publicActions,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { mainnet } from "viem/chains";
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

export class InvalidLabelNameError extends Error {
  constructor(public readonly labelName: any) {
    super(`Invalid label name: ${labelName}`);
    this.name = "InvalidLabelNameError";
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
  mainnetRpcUrl: string;
  mainnetBaseRegistrarAddress?: Address;
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

// ENS v1 BaseRegistrar on Ethereum mainnet
const BASE_REGISTRAR_ADDRESS = "0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85" as Address;
const BASE_REGISTRAR_ABI = [
  {
    inputs: [{ internalType: "uint256", name: "id", type: "uint256" }],
    name: "nameExpires",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

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

  processingName(name: string, index: number, total: number): void {
    this.raw(
      cyan(`[${index}/${total}] Processing: ${bold(name)}.eth`),
      `[${index}/${total}] Processing: ${name}.eth`
    );
  }

  finishedName(name: string, result: 'registered' | 'skipped' | 'failed'): void {
    const icon = result === 'registered' ? '✓' : result === 'skipped' ? '⊘' : '✗';
    const color = result === 'registered' ? green : result === 'skipped' ? yellow : red;
    this.raw(
      color(`${icon} Done: ${bold(name)}.eth`) + dim(` (${result})`),
      `${icon} Done: ${name}.eth (${result})`
    );
  }

  registering(name: string, expiry: string): void {
    this.raw(
      blue(`  → Registering on namechain`) + dim(` (expires: ${expiry})`),
      `  → Registering on namechain (expires: ${expiry})`
    );
  }

  registered(tx: string): void {
    this.raw(
      green(`  → ✓ Registered successfully`) + dim(` (tx: ${tx})`),
      `  → ✓ Registered successfully (tx: ${tx})`
    );
  }

  alreadyRegistered(owner: string): void {
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

  verifyingMainnet(name: string): void {
    this.raw(
      dim(`  → Checking mainnet status for ${name}.eth...`),
      `  → Checking mainnet status for ${name}.eth...`
    );
  }

  mainnetVerified(name: string, expiry: string): void {
    this.raw(
      green(`  → ✓ Verified on mainnet`) + dim(` (expires: ${expiry})`),
      `  → ✓ Verified on mainnet (expires: ${expiry})`
    );
  }

  mainnetNotRegistered(name: string, reason: string): void {
    this.raw(
      yellow(`  → ⊘ Not registered on mainnet: ${reason}`),
      `  → ⊘ Not registered on mainnet: ${reason}`
    );
  }

  skippingInvalidName(domainName: string): void {
    this.raw(
      yellow(`  → ⊘ Skipping: ${bold(domainName)}`) + dim(` (invalid label name)`),
      `  → ⊘ Skipping: ${domainName} (invalid label name)`
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

// Mainnet verification
interface MainnetVerificationResult {
  isRegistered: boolean;
  expiry: bigint;
}

async function verifyNameOnMainnet(
  labelName: string,
  mainnetClient: any,
  baseRegistrarAddress: Address = BASE_REGISTRAR_ADDRESS
): Promise<MainnetVerificationResult> {
  if (!labelName || typeof labelName !== 'string' || labelName.trim() === '') {
    throw new InvalidLabelNameError(labelName);
  }

  const tokenId = keccak256(toHex(labelName));

  const expiry = await mainnetClient.readContract({
    address: baseRegistrarAddress,
    abi: BASE_REGISTRAR_ABI,
    functionName: "nameExpires",
    args: [tokenId],
  });

  const currentTimestamp = BigInt(Math.floor(Date.now() / 1000));
  const isRegistered = expiry > 0n && expiry > currentTimestamp;

  return { isRegistered, expiry };
}

// TheGraph queries
async function fetchRegistrations(
  config: PreMigrationConfig,
  skip: number,
  first: number,
  fetchFn: typeof fetch = fetch
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

  const response = await fetchFn(endpoint, {
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
  config: PreMigrationConfig,
  fetchFn: typeof fetch = fetch
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
        config.batchSize,
        fetchFn
      );

      if (registrations.length === 0) {
        hasMore = false;
        break;
      }

      // Filter out invalid registrations (null or empty labelName)
      const validRegistrations = registrations.filter((reg) => {
        if (!reg.labelName || typeof reg.labelName !== 'string' || reg.labelName.trim() === '') {
          logger.skippingInvalidName(reg.domain.name);
          return false;
        }
        return true;
      });

      allRegistrations.push(...validRegistrations);
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
  mainnetClient: any,
  retries = 0
): Promise<RegistrationResult> {
  const { labelName } = registration;

  try {
    // Check if name is already registered in namechain first
    try {
      const [tokenId] = await registry.read.getNameData([labelName]);
      const owner = await registry.read.ownerOf([tokenId]);

      if (owner !== zeroAddress) {
        // Verify the owner is the bridge controller (from this migration)
        if (owner.toLowerCase() !== config.bridgeControllerAddress.toLowerCase()) {
          logger.error(`Name ${labelName}.eth is already registered but owned by unexpected address: ${owner}`);
          throw new UnexpectedOwnerError(labelName, owner, config.bridgeControllerAddress);
        }

        logger.alreadyRegistered(owner.substring(0, 10));
        return { labelName, success: true, skipped: true };
      }
    } catch (error) {
      // If it's our validation error, re-throw it
      if (error instanceof UnexpectedOwnerError) {
        throw error;
      }
      // Otherwise, name doesn't exist or error checking - proceed with mainnet verification
    }

    // Verify name is still registered on mainnet
    logger.verifyingMainnet(labelName);
    const mainnetResult = await verifyNameOnMainnet(
      labelName,
      mainnetClient,
      config.mainnetBaseRegistrarAddress
    );

    if (!mainnetResult.isRegistered) {
      const reason = mainnetResult.expiry === 0n
        ? "never registered or fully expired"
        : "expired";
      logger.mainnetNotRegistered(labelName, reason);
      return { labelName, success: true, skipped: true };
    }

    const expiryDateFormatted = new Date(Number(mainnetResult.expiry) * 1000).toISOString().split('T')[0];
    logger.mainnetVerified(labelName, expiryDateFormatted);

    // Use mainnet expiry for registration
    const expires = mainnetResult.expiry;

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

    logger.registered(hash);
    return { labelName, success: true, txHash: hash };
  } catch (error) {
    // Don't retry validation errors - these are permanent failures
    if (error instanceof UnexpectedOwnerError || error instanceof InvalidLabelNameError) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.failed(labelName, errorMessage, undefined, MAX_RETRIES);
      return { labelName, success: false, error: errorMessage };
    }

    const errorMessage = error instanceof Error ? error.message : String(error);

    if (retries < MAX_RETRIES) {
      logger.failed(labelName, errorMessage, retries + 1, MAX_RETRIES);
      await new Promise((resolve) => setTimeout(resolve, 1000 * (retries + 1)));
      return registerName(client, registry, config, registration, mainnetClient, retries + 1);
    }

    logger.failed(labelName, errorMessage, undefined, MAX_RETRIES);
    return { labelName, success: false, error: errorMessage };
  }
}

export async function batchRegisterNames(
  config: PreMigrationConfig,
  registrations: ENSRegistration[],
  providedClient?: any,
  providedRegistry?: any,
  providedMainnetClient?: any
): Promise<void> {
  const client = providedClient || createWalletClient({
    account: privateKeyToAccount(config.privateKey),
    transport: http(config.rpcUrl, {
      retryCount: 0,
      timeout: 30000,
    }),
  }).extend(publicActions);

  const registry = providedRegistry || getContract({
    address: config.registryAddress,
    abi: artifacts.PermissionedRegistry.abi,
    client,
  });

  const mainnetClient = providedMainnetClient || createPublicClient({
    chain: mainnet,
    transport: http(config.mainnetRpcUrl, {
      retryCount: 3,
      timeout: 30000,
    }),
  });

  logger.info(`\nStarting registration process...`);
  logger.info(`Total names to register: ${registrations.length}`);
  logger.info(`TheGraph batch size: ${config.batchSize}`);
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

    // Log start of processing
    logger.processingName(registration.labelName, i + 1, registrations.length);

    const result = await registerName(client, registry, config, registration, mainnetClient);
    results.push(result);

    // Determine result type and log completion
    let resultType: 'registered' | 'skipped' | 'failed';
    if (result.skipped) {
      checkpoint.skippedCount++;
      resultType = 'skipped';
      // Don't increment totalProcessed for skipped names
    } else if (result.success) {
      checkpoint.successCount++;
      checkpoint.totalProcessed++;
      resultType = 'registered';
    } else {
      checkpoint.failureCount++;
      checkpoint.totalProcessed++;
      resultType = 'failed';
    }

    logger.finishedName(registration.labelName, resultType);

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
    .requiredOption("--namechain-rpc-url <url>", "Namechain (v2) RPC endpoint")
    .option("--mainnet-rpc-url <url>", "Mainnet RPC endpoint for verification", "https://mainnet.gateway.tenderly.co/")
    .requiredOption("--namechain-registry <address>", "ETH Registry contract address")
    .requiredOption("--namechain-bridge-controller <address>", "L2BridgeController address")
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
    rpcUrl: opts.namechainRpcUrl,
    mainnetRpcUrl: opts.mainnetRpcUrl,
    registryAddress: opts.namechainRegistry as Address,
    bridgeControllerAddress: opts.namechainBridgeController as Address,
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
    logger.config('Namechain RPC URL', config.rpcUrl);
    logger.config('Mainnet RPC URL', config.mainnetRpcUrl);
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
    const registrations = await fetchAllRegistrations(config); // Uses default fetch

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
