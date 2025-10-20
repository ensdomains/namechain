#!/usr/bin/env bun

import { artifacts } from "@rocketh";
import { Command } from "commander";
import { writeFileSync, existsSync, readFileSync, rmSync, createReadStream } from "node:fs";
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

// Helper function to determine if an error is retriable
function isRetriableError(error: any): boolean {
  const message = error?.message?.toLowerCase() || '';
  return (
    message.includes('timeout') ||
    message.includes('network') ||
    message.includes('rate limit') ||
    message.includes('connection') ||
    message.includes('econnrefused') ||
    message.includes('etimedout')
  );
}

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
  labelName: string;
  lineNumber: number;
}

export interface BatchRegistrarName {
  label: string;
  owner: Address;
  registry: Address;
  resolver: Address;
  roleBitmap: bigint;
  expires: bigint;
}

export interface PreMigrationConfig {
  rpcUrl: string;
  mainnetRpcUrl: string;
  mainnetBaseRegistrarAddress?: Address;
  registryAddress: Address;
  bridgeControllerAddress: Address;
  privateKey: `0x${string}`;
  csvFilePath: string;
  batchSize: number;
  startIndex: number;
  limit: number | null;
  dryRun: boolean;
  roleBitmap: bigint;
  continue?: boolean;
  disableCheckpoint?: boolean;
  batchRegistrarAddress?: Address;
}

export interface Checkpoint {
  lastProcessedLineNumber: number;
  totalProcessed: number;
  totalExpected: number;
  successCount: number;
  failureCount: number;
  skippedCount: number;
  invalidLabelCount: number;
  timestamp: string;
  batchRegistrarAddress?: Address;
}

// Constants
const CHECKPOINT_FILE = "preMigration-checkpoint.json";
const ERROR_LOG_FILE = "preMigration-errors.log";
const INFO_LOG_FILE = "preMigration.log";
const MAX_RETRIES = 3;

// Configuration constants
const RPC_TIMEOUT_MS = 30000;
const PROGRESS_LOG_INTERVAL = 10;

// ENS v1 BaseRegistrar on Ethereum mainnet
const BASE_REGISTRAR_ADDRESS = "0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85" as Address;
const PRE_MIGRATION_RESOLVER = "0x0000000000000000000000000000000000000001" as Address;
const BASE_REGISTRAR_ABI = [
  {
    inputs: [{ internalType: "uint256", name: "id", type: "uint256" }],
    name: "nameExpires",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

/**
 * Checkpoint system behavior:
 * - Default: Always start fresh (checkpoint file ignored)
 * - With --continue: Resume from checkpoint if exists
 * - With disableCheckpoint: true: No checkpoint loading/saving (tests only)
 *
 * Checkpoints save progress periodically and on completion,
 * allowing resuming long migrations if interrupted.
 */
export function createFreshCheckpoint(): Checkpoint {
  return {
    lastProcessedLineNumber: -1,
    totalProcessed: 0,
    totalExpected: 0,
    successCount: 0,
    failureCount: 0,
    skippedCount: 0,
    invalidLabelCount: 0,
    timestamp: new Date().toISOString(),
  };
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
export function loadCheckpoint(): Checkpoint | null {
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

export function saveCheckpoint(checkpoint: Checkpoint): void {
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

/**
 * Verifies if an ENS name is currently registered on Ethereum mainnet.
 *
 * @param labelName - The label name (without .eth suffix) to verify
 * @param mainnetClient - Viem public client configured for mainnet
 * @param baseRegistrarAddress - Address of the ENS BaseRegistrar contract
 * @returns Verification result with registration status and expiry timestamp
 * @throws {InvalidLabelNameError} If the label name is invalid or empty
 */
export async function verifyNameOnMainnet(
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

/**
 * Deploys or retrieves the BatchRegistrar contract.
 * If a checkpoint address is provided and has code deployed, reuses it.
 * Otherwise deploys a new instance.
 *
 * @param client - Viem wallet client for deployment
 * @param registryAddress - Address of the ETH registry contract
 * @param checkpointAddress - Previously deployed address from checkpoint (if any)
 * @returns BatchRegistrar contract instance and its address
 */
export async function deployBatchRegistrar(
  client: any,
  registryAddress: Address,
  checkpointAddress?: Address
): Promise<{ contract: any; address: Address }> {
  const batchRegistrarArtifact = artifacts.BatchRegistrar;

  // Check if we can reuse a previously deployed BatchRegistrar from checkpoint
  if (checkpointAddress) {
    const existingCode = await client.getCode({ address: checkpointAddress });
    if (existingCode && existingCode !== "0x") {
      logger.success(`Reusing BatchRegistrar from checkpoint at ${checkpointAddress}`);
      return {
        contract: getContract({
          address: checkpointAddress,
          abi: batchRegistrarArtifact.abi,
          client,
        }),
        address: checkpointAddress,
      };
    } else {
      logger.warning(`Checkpoint address ${checkpointAddress} has no code, deploying new instance`);
    }
  }

  logger.info("Deploying BatchRegistrar...");

  const hash = await client.deployContract({
    abi: batchRegistrarArtifact.abi,
    bytecode: batchRegistrarArtifact.bytecode as `0x${string}`,
    args: [registryAddress],
  });

  const receipt = await client.waitForTransactionReceipt({ hash });
  const deployedAddress = receipt.contractAddress;

  logger.success(`BatchRegistrar deployed at ${deployedAddress}`);

  // Verify deployment
  const code = await client.getCode({ address: deployedAddress });
  if (!code || code === "0x") {
    throw new Error(`BatchRegistrar deployment failed - no code at ${deployedAddress}`);
  }

  return {
    contract: getContract({
      address: deployedAddress,
      abi: batchRegistrarArtifact.abi,
      client,
    }),
    address: deployedAddress,
  };
}

/**
 * Reads ENS registrations from a CSV file in batches.
 * Returns an async generator that yields batches of registrations with line numbers.
 *
 * @param csvFilePath - Path to the CSV file
 * @param batchSize - Number of registrations per batch
 * @param startLineNumber - Skip to this CSV line number before starting
 * @param limit - Maximum total number of registrations to read
 * @returns Async generator yielding batches of ENS registrations with their CSV line numbers
 */
async function* readCSVInBatches(
  csvFilePath: string,
  batchSize: number,
  startLineNumber: number = 0,
  limit: number | null = null
): AsyncGenerator<ENSRegistration[]> {
  const readline = await import("node:readline");

  const fileStream = createReadStream(csvFilePath);
  const rl = readline.createInterface({
    input: fileStream,
    crlfDelay: Infinity,
  });

  let lineNumber = 0;
  let processedCount = 0;
  let batch: ENSRegistration[] = [];
  let headerSkipped = false;

  for await (const line of rl) {
    if (!headerSkipped) {
      headerSkipped = true;
      continue;
    }

    if (lineNumber <= startLineNumber) {
      lineNumber++;
      continue;
    }

    if (limit && processedCount >= limit) {
      break;
    }

    const parts = parseCSVLine(line);
    if (parts.length >= 7) {
      const labelName = parts[6].trim();
      if (labelName && labelName !== '') {
        batch.push({ labelName, lineNumber });
        processedCount++;

        if (batch.length >= batchSize) {
          yield batch;
          batch = [];
        }
      }
    }

    lineNumber++;
  }

  if (batch.length > 0) {
    yield batch;
  }
}

/**
 * Parses a CSV line handling quoted fields and commas within quotes.
 */
function parseCSVLine(line: string): string[] {
  const result: string[] = [];
  let current = '';
  let inQuotes = false;

  for (let i = 0; i < line.length; i++) {
    const char = line[i];

    if (char === '"') {
      if (inQuotes && line[i + 1] === '"') {
        current += '"';
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char === ',' && !inQuotes) {
      result.push(current);
      current = '';
    } else {
      current += char;
    }
  }

  result.push(current);
  return result;
}

// Streaming batch processing - reads from CSV and registers one batch at a time
async function fetchAndRegisterInBatches(
  config: PreMigrationConfig,
): Promise<void> {
  // Load checkpoint if continuing
  let checkpoint: Checkpoint | null = null;

  if (config.continue) {
    checkpoint = loadCheckpoint();
    if (checkpoint) {
      logger.info(`Resuming from checkpoint: ${checkpoint.totalProcessed} names already processed from line ${checkpoint.lastProcessedLineNumber}`);
      config.startIndex = checkpoint.lastProcessedLineNumber;
    }
  }

  if (!checkpoint) {
    checkpoint = createFreshCheckpoint();
  }

  // Client instances shared across batch processing for connection reuse
  const client = createWalletClient({
    account: privateKeyToAccount(config.privateKey),
    transport: http(config.rpcUrl, { retryCount: 0, timeout: RPC_TIMEOUT_MS }),
  }).extend(publicActions);

  const registry = getContract({
    address: config.registryAddress,
    abi: artifacts.PermissionedRegistry.abi,
    client,
  });

  const mainnetClient = createPublicClient({
    chain: mainnet,
    transport: http(config.mainnetRpcUrl, { retryCount: 3, timeout: RPC_TIMEOUT_MS }),
  });

  // Deploy or get BatchRegistrar
  const { contract: batchRegistrar, address: batchRegistrarAddress } = await deployBatchRegistrar(
    client,
    config.registryAddress,
    checkpoint.batchRegistrarAddress
  );

  // Update checkpoint with BatchRegistrar address
  checkpoint.batchRegistrarAddress = batchRegistrarAddress;

  // Grant REGISTRAR role to BatchRegistrar if needed
  const hasRole = await registry.read.hasRootRoles([
    ROLES.OWNER.EAC.REGISTRAR,
    batchRegistrarAddress,
  ]);

  if (!hasRole) {
    logger.info("Granting REGISTRAR role to BatchRegistrar...");
    const hash = await (registry.write.grantRootRoles as any)([
      ROLES.OWNER.EAC.REGISTRAR,
      batchRegistrarAddress,
    ]);
    await client.waitForTransactionReceipt({ hash });
    logger.success("REGISTRAR role granted to BatchRegistrar");
  } else {
    logger.info("BatchRegistrar already has REGISTRAR role");
  }

  logger.info(`\nReading CSV file and registering in batches of ${config.batchSize}...`);
  logger.info(`CSV file: ${config.csvFilePath}`);

  const batchGenerator = readCSVInBatches(
    config.csvFilePath,
    config.batchSize,
    config.startIndex,
    config.limit
  );

  for await (const batch of batchGenerator) {
    try {
      // Track expected total including all names in batch
      checkpoint.totalExpected += batch.length;

      // Separate valid from invalid registrations for processing
      let invalidLabelsInBatch = 0;
      let lastInvalidLineNumber = checkpoint.lastProcessedLineNumber;
      const validBatch = batch.filter((reg) => {
        if (!reg.labelName || typeof reg.labelName !== 'string' || reg.labelName.trim() === '') {
          logger.skippingInvalidName(reg.labelName || 'unknown');
          invalidLabelsInBatch++;
          checkpoint!.invalidLabelCount++;
          checkpoint!.totalProcessed++;
          lastInvalidLineNumber = reg.lineNumber;
          return false;
        }
        return true;
      });

      if (invalidLabelsInBatch > 0) {
        checkpoint.lastProcessedLineNumber = lastInvalidLineNumber;
        if (!config.disableCheckpoint) {
          saveCheckpoint(checkpoint);
        }
      }

      logger.info(
        `\nRead ${batch.length} registrations from CSV (${invalidLabelsInBatch} invalid labels filtered). ` +
        `Starting registration of ${validBatch.length} valid names...`
      );

      // Process valid batch immediately
      if (validBatch.length > 0) {
        checkpoint = await processBatch(
          config,
          validBatch,
          client,
          registry,
          batchRegistrar,
          mainnetClient,
          checkpoint
        );
      }

      // Show batch summary
      logger.info(
        `Batch complete. Total: ${checkpoint.totalProcessed} processed ` +
        `(${checkpoint.successCount} registered, ${checkpoint.skippedCount} skipped, ` +
        `${checkpoint.invalidLabelCount} invalid, ${checkpoint.failureCount} failed)`
      );

      // Check if we've reached the limit
      if (config.limit && checkpoint.totalProcessed >= config.limit) {
        logger.info(`\nReached limit of ${config.limit} names. Stopping.`);
        break;
      }
    } catch (error) {
      logger.error(`Failed to process batch: ${error}`);
      throw error;
    }
  }

  // Final summary
  printFinalSummary(checkpoint);
}

// Process a single batch of registrations using BatchRegistrar
async function processBatch(
  config: PreMigrationConfig,
  registrations: ENSRegistration[],
  client: any,
  registry: any,
  batchRegistrar: any,
  mainnetClient: any,
  checkpoint: Checkpoint
): Promise<Checkpoint> {
  const batchNames: BatchRegistrarName[] = [];
  let lastLineNumber = checkpoint.lastProcessedLineNumber;

  // First pass: verify all names on mainnet and check if already registered
  for (let i = 0; i < registrations.length; i++) {
    const registration = registrations[i];
    const globalIndex = checkpoint.totalProcessed + i + 1;
    lastLineNumber = registration.lineNumber;

    logger.processingName(registration.labelName, globalIndex, checkpoint.totalExpected);

    try {
      // Check if name is already registered in namechain
      try {
        const [tokenId] = await registry.read.getNameData([registration.labelName]);
        const owner = await registry.read.ownerOf([tokenId]);

        if (owner !== zeroAddress) {
          if (owner.toLowerCase() !== config.bridgeControllerAddress.toLowerCase()) {
            logger.error(`Name ${registration.labelName}.eth is already registered but owned by unexpected address: ${owner}`);
            checkpoint.failureCount++;
            logger.finishedName(registration.labelName, 'failed');
            continue;
          }

          logger.alreadyRegistered(owner.substring(0, 10));
          checkpoint.skippedCount++;
          logger.finishedName(registration.labelName, 'skipped');
          continue;
        }
      } catch (error) {
        // Name not found - proceed with mainnet verification
      }

      // Verify name is still registered on mainnet
      logger.verifyingMainnet(registration.labelName);
      const mainnetResult = await verifyNameOnMainnet(
        registration.labelName,
        mainnetClient,
        config.mainnetBaseRegistrarAddress
      );

      if (!mainnetResult.isRegistered) {
        const reason = mainnetResult.expiry === 0n
          ? "never registered or fully expired"
          : "expired";
        logger.mainnetNotRegistered(registration.labelName, reason);
        checkpoint.skippedCount++;
        logger.finishedName(registration.labelName, 'skipped');
        continue;
      }

      const expiryDateFormatted = new Date(Number(mainnetResult.expiry) * 1000).toISOString().split('T')[0];
      logger.mainnetVerified(registration.labelName, expiryDateFormatted);

      // Add to batch
      batchNames.push({
        label: registration.labelName,
        owner: config.bridgeControllerAddress,
        registry: zeroAddress,
        resolver: PRE_MIGRATION_RESOLVER,
        roleBitmap: config.roleBitmap,
        expires: mainnetResult.expiry,
      });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.failed(registration.labelName, errorMessage, undefined, MAX_RETRIES);
      checkpoint.failureCount++;
      logger.finishedName(registration.labelName, 'failed');
    }

    // Update and save checkpoint after each name to handle interruptions
    checkpoint.totalProcessed++;
    checkpoint.lastProcessedLineNumber = lastLineNumber;
    checkpoint.timestamp = new Date().toISOString();

    if (!config.disableCheckpoint) {
      saveCheckpoint(checkpoint);
    }
  }

  // Final checkpoint update (counts already updated incrementally above)
  checkpoint.lastProcessedLineNumber = lastLineNumber;

  // Second pass: batch register all valid names
  if (batchNames.length > 0 && !config.dryRun) {
    logger.info(`\nBatch registering ${batchNames.length} names...`);

    try {
      const hash = await batchRegistrar.write.batchRegister([batchNames]);
      await client.waitForTransactionReceipt({ hash });

      logger.success(`Batch registration successful (tx: ${hash})`);
      checkpoint.successCount += batchNames.length;

      // Log each registered name
      for (const name of batchNames) {
        logger.registered(hash);
        logger.finishedName(name.label, 'registered');
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(`Batch registration failed: ${errorMessage}`);
      checkpoint.failureCount += batchNames.length;

      for (const name of batchNames) {
        logger.failed(name.label, errorMessage, undefined, MAX_RETRIES);
        logger.finishedName(name.label, 'failed');
      }
    }
  } else if (batchNames.length > 0 && config.dryRun) {
    logger.info(`\nDry run: Would batch register ${batchNames.length} names`);
    checkpoint.successCount += batchNames.length;

    for (const name of batchNames) {
      logger.dryRun();
      logger.finishedName(name.label, 'registered');
    }
  }

  checkpoint.timestamp = new Date().toISOString();

  // Save checkpoint
  if (!config.disableCheckpoint) {
    saveCheckpoint(checkpoint);
  }

  return checkpoint;
}

// Helper to calculate success rate percentage
function calculateSuccessRate(successCount: number, totalAttempts: number): number {
  return totalAttempts > 0 ? Math.round((successCount / totalAttempts) * 100) : 0;
}

// Print final summary after all processing
function printFinalSummary(checkpoint: Checkpoint): void {
  const actualRegistrations = checkpoint.successCount + checkpoint.failureCount;

  logger.info('');
  logger.divider();
  logger.header('Pre-Migration Complete');
  logger.divider();

  logger.config('Total names processed', checkpoint.totalProcessed);
  logger.config('Successfully registered', green(checkpoint.successCount.toString()));
  logger.config('Skipped (already registered/expired)', yellow(checkpoint.skippedCount.toString()));
  logger.config('Invalid labels', yellow(checkpoint.invalidLabelCount.toString()));
  logger.config('Failed (other errors)', checkpoint.failureCount > 0 ? red(checkpoint.failureCount.toString()) : checkpoint.failureCount);
  logger.config('Actual registrations attempted', actualRegistrations);

  const rate = calculateSuccessRate(checkpoint.successCount, actualRegistrations);
  if (actualRegistrations > 0) {
    logger.config('Registration success rate', `${rate}%`);
  }

  logger.divider();

  if (checkpoint.failureCount > 0) {
    logger.warning(`\nSome registrations failed. Check ${ERROR_LOG_FILE} for details.`);
  }
}

/**
 * Batch registers multiple ENS names for testing purposes.
 * Processes a pre-fetched list of registrations using BatchRegistrar.
 *
 * @param config - Pre-migration configuration
 * @param registrations - Pre-fetched array of registrations to process
 * @param providedClient - Optional wallet client (created if not provided)
 * @param providedRegistry - Optional registry contract (created if not provided)
 */
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
      timeout: RPC_TIMEOUT_MS,
    }),
  }).extend(publicActions);

  const registry = providedRegistry || getContract({
    address: config.registryAddress,
    abi: artifacts.PermissionedRegistry.abi,
    client,
  });

  const mainnetClient = createPublicClient({
    chain: mainnet,
    transport: http(config.mainnetRpcUrl, {
      retryCount: 3,
      timeout: RPC_TIMEOUT_MS,
    }),
  });

  // Deploy or get BatchRegistrar
  const { contract: batchRegistrar, address: batchRegistrarAddress } = await deployBatchRegistrar(
    client,
    config.registryAddress,
    config.batchRegistrarAddress
  );

  // Grant REGISTRAR role to BatchRegistrar if needed
  const hasRole = await registry.read.hasRootRoles([
    ROLES.OWNER.EAC.REGISTRAR,
    batchRegistrarAddress,
  ]);

  if (!hasRole) {
    const hash = await (registry.write.grantRootRoles as any)([
      ROLES.OWNER.EAC.REGISTRAR,
      batchRegistrarAddress,
    ]);
    await client.waitForTransactionReceipt({ hash });
  }

  // Load checkpoint based on configuration
  let checkpoint: Checkpoint;
  if (config.disableCheckpoint) {
    checkpoint = createFreshCheckpoint();
    checkpoint.totalExpected = registrations.length;
  } else if (config.continue) {
    const loaded = loadCheckpoint();
    if (loaded) {
      checkpoint = {
        ...loaded,
        skippedCount: loaded.skippedCount ?? 0,
        invalidLabelCount: loaded.invalidLabelCount ?? 0,
        totalExpected: (loaded.totalExpected ?? loaded.totalProcessed) + registrations.length,
      };
    } else {
      checkpoint = createFreshCheckpoint();
      checkpoint.totalExpected = registrations.length;
    }
  } else {
    checkpoint = createFreshCheckpoint();
    checkpoint.totalExpected = registrations.length;
  }

  // Process in a single batch
  await processBatch(
    config,
    registrations,
    client,
    registry,
    batchRegistrar,
    mainnetClient,
    checkpoint
  );

  // Print summary
  printFinalSummary(checkpoint);
}

/**
 * Main entry point for the pre-migration CLI tool.
 * Parses command-line arguments and orchestrates the migration process.
 *
 * @param argv - Command-line arguments (defaults to process.argv)
 */
export async function main(argv = process.argv): Promise<void> {
  const program = new Command()
    .name("premigrate")
    .description("Pre-migrate ENS .eth 2LDs from Mainnet to v2. By default starts fresh. Use --continue to resume from checkpoint.")
    .requiredOption("--namechain-rpc-url <url>", "Namechain (v2) RPC endpoint")
    .option("--mainnet-rpc-url <url>", "Mainnet RPC endpoint for verification", "https://mainnet.gateway.tenderly.co/")
    .requiredOption("--namechain-registry <address>", "ETH Registry contract address")
    .requiredOption("--namechain-bridge-controller <address>", "L2BridgeController address")
    .requiredOption("--private-key <key>", "Deployer private key (has REGISTRAR role)")
    .requiredOption("--csv-file <path>", "Path to CSV file containing ENS registrations")
    .option("--batch-size <number>", "Number of names to process per batch", "50")
    .option("--start-index <number>", "Starting index for resuming partial migrations", "0")
    .option("--limit <number>", "Maximum total number of names to process and register")
    .option("--dry-run", "Simulate without executing transactions", false)
    .option("--continue", "Continue from previous checkpoint if it exists", false)
    .option("--role-bitmap <hex>", "Custom role bitmap (hex string) for when registering names");

  program.parse(argv);
  const opts = program.opts();

  const config: PreMigrationConfig = {
    rpcUrl: opts.namechainRpcUrl,
    mainnetRpcUrl: opts.mainnetRpcUrl,
    registryAddress: opts.namechainRegistry as Address,
    bridgeControllerAddress: opts.namechainBridgeController as Address,
    privateKey: opts.privateKey as `0x${string}`,
    csvFilePath: opts.csvFile,
    batchSize: parseInt(opts.batchSize) || 100,
    startIndex: parseInt(opts.startIndex) || 0,
    limit: opts.limit ? parseInt(opts.limit) : null,
    dryRun: opts.dryRun,
    continue: opts.continue,
    roleBitmap: opts.roleBitmap ? BigInt(opts.roleBitmap) : ROLES.ALL,
  };

  try {
    logger.header("ENS Pre-Migration Script");
    logger.divider();

    logger.info(`Configuration:`);
    logger.config('Namechain RPC URL', config.rpcUrl);
    logger.config('Mainnet RPC URL', config.mainnetRpcUrl);
    logger.config('Registry', config.registryAddress);
    logger.config('Bridge Controller', config.bridgeControllerAddress);
    logger.config('CSV File', config.csvFilePath);
    logger.config('Batch Size', config.batchSize);
    logger.config('Limit', config.limit ?? "none");
    logger.config('Dry Run', config.dryRun);
    logger.config('Continue Mode', config.continue ?? false);
    if (config.continue && loadCheckpoint()) {
      const cp = loadCheckpoint()!;
      const invalidCount = cp.invalidLabelCount ?? 0;
      const lastLine = cp.lastProcessedLineNumber ?? -1;
      logger.config('Checkpoint Found', `${cp.totalProcessed} processed, ${cp.skippedCount} skipped, ${invalidCount} invalid, ${cp.failureCount} failed (last line: ${lastLine})`);
      config.startIndex = lastLine;
      logger.info(`Resuming from CSV line ${config.startIndex}`);
    }
    logger.config('Role Bitmap', `0x${config.roleBitmap.toString(16)}`);
    logger.info("");

    // Read CSV and register in streaming batches
    await fetchAndRegisterInBatches(config);

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
