#!/usr/bin/env bun

import { Command } from "commander";
import { createReadStream, existsSync, readFileSync, writeFileSync } from "node:fs";
import {
  createPublicClient,
  createWalletClient,
  getContract,
  http,
  keccak256,
  publicActions,
  toHex,
  zeroAddress,
  type Address
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { mainnet } from "viem/chains";
import { ROLES } from "./deploy-constants.js";
import { waitForSuccessfulTransactionReceipt } from "../test/utils/waitForSuccessfulTransactionReceipt.js";
import {
  blue,
  bold,
  cyan,
  dim,
  green,
  Logger,
  magenta,
  red,
  yellow,
} from "./logger.js";

// ABI fragments for contracts
const PERMISSIONED_REGISTRY_ABI = [
  {
    inputs: [{ name: "label", type: "string" }],
    name: "getNameData",
    outputs: [
      { name: "tokenId", type: "uint256" },
      {
        name: "entry",
        type: "tuple",
        components: [
          { name: "expiry", type: "uint64" },
          { name: "subregistry", type: "address" },
          { name: "resolver", type: "address" },
          { name: "eacVersionId", type: "uint8" },
          { name: "tokenVersionId", type: "uint8" },
        ],
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "tokenId", type: "uint256" }],
    name: "ownerOf",
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { name: "roleBitmap", type: "uint256" },
      { name: "account", type: "address" },
    ],
    name: "hasRootRoles",
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { name: "roleBitmap", type: "uint256" },
      { name: "account", type: "address" },
    ],
    name: "grantRootRoles",
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;

const BATCH_REGISTRAR_ABI = [
  {
    inputs: [{ name: "ethRegistry_", type: "address" }],
    stateMutability: "nonpayable",
    type: "constructor",
  },
  {
    inputs: [
      {
        name: "names",
        type: "tuple[]",
        components: [
          { name: "label", type: "string" },
          { name: "owner", type: "address" },
          { name: "registry", type: "address" },
          { name: "resolver", type: "address" },
          { name: "roleBitmap", type: "uint256" },
          { name: "expires", type: "uint64" },
        ],
      },
    ],
    name: "batchRegister",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;

const BATCH_REGISTRAR_BYTECODE = "0x60a060405234801561000f575f80fd5b506040516106ac3803806106ac83398101604081905261002e91610040565b6001600160a01b031660805261006d565b5f60208284031215610050575f80fd5b81516001600160a01b0381168114610066575f80fd5b9392505050565b60805161061b6100915f395f8181609a01528181610174015261027a015261061b5ff3fe608060405234801561000f575f80fd5b5060043610610034575f3560e01c80632b4b5a9714610038578063c6c2d1111461004d575b5f80fd5b61004b6100463660046103d1565b610098565b005b6100757f000000000000000000000000000000000000000000000000000000000000000081565b6040516001600160a01b0390911681526020015b60405180910390f35b7f00000000000000000000000000000000000000000000000000000000000000005f5b82811015610261575f8484838181106100d6576100d66104b7565b90506020028101906100e891906104cb565b6100f6906020810190610510565b604051610104929190610559565b604051809103902090505f7f00000000000000000000000000000000000000000000000000000000000000006001600160a01b03166382c414a88888878181106101505761015061057e565b905060200281019061016291906104cb565b610170906020810190610510565b7f00000000000000000000000000000000000000000000000000000000000000006040518463ffffffff1660e01b81526004016101af939291906105d7565b60c060405180830381865afa1580156101ca573d5f803e3d5ffd5b505050506040513d601f19601f820116820180604052508101906101ee919061069e565b509050805f015167ffffffffffffffff16158061021857508051428167ffffffffffffffff16115b1561024f576040516325c6d4a960e21b815260048101849052670de0b6b3a76400006024820152604401604051809103905ffd5b508061025a816106c2565b91506100bb565b50505050565b634e487b7160e01b5f52604160045260245ffd5b604051601f8201601f1916810167ffffffffffffffff811182821017156102a4576102a4610267565b604052919050565b5f67ffffffffffffffff8211156102c5576102c5610267565b50601f01601f191660200190565b5f82601f8301126102e2575f80fd5b81356102f56102f0826102ac565b61027b565b818152846020838601011115610309575f80fd5b816020850160208301375f918101602001919091529392505050565b6001600160a01b0381168114610339575f80fd5b50565b803561034781610325565b919050565b803567ffffffffffffffff81168114610347575f80fd5b5f60c08284031215610373575f80fd5b60405160c0810181811067ffffffffffffffff8211171561039657610396610267565b80604052508091508235815260208301356103b081610325565b602082015260408301356103c381610325565b6040820152606083013560608201526080830135608082015260a083013560a082015250919050565b5f805f606084860312156103fe575f80fd5b833567ffffffffffffffff80821115610415575f80fd5b818601915086601f830112610428575f80fd5b813560208282111561043c5761043c610267565b8160051b61044b82820161027b565b928352848101820192828101908b851115610464575f80fd5b83870192505b8483101561048d57823582811115610480575f80fd5b61048e8d86838b01016102d3565b835250918301919083019061046a565b98506104b6915050879050818a0161033c565b9550505b5050506104c78560408601610363565b90509250925092565b5f8235609e198336030181126104e4575f80fd5b9190910192915050565b5f67ffffffffffffffff82111561050757610507610267565b50601f01601f191660200190565b5f8083357fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe1843603018112610548575f80fd5b83018035915067ffffffffffffffff821115610562575f80fd5b60200191503681900382131561057657815f80fd5b9250929050565b634e487b7160e01b5f52603260045260245ffd5b5f81518084528060208401602086015e5f602082860101526020601f19601f83011685010191505092915050565b602081525f6105d26020830184610591565b9392505050565b5f60c082018583526020858185015260c06040850152818554808452858301915060e0860186525f86815283812090915b828110156106285781548452600191820191850161060a565b50508293506060860192909252506080840152915060a0830152509392505050565b5f6106586102f0846102ac565b905082815283838301111561066b575f80fd5b828260208301375f602084830101529392505050565b5f82601f830112610690575f80fd5b6105d28383516020850161064a565b5f602082840312156106ae575f80fd5b81516105d281610325565b634e487b7160e01b5f52601160045260245ffd5b5f600182016106d9576106d96106b9565b506001019056fea26469706673582212207d42a9c7c4b84c9e1b5b8c8f0e5d6a3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f64736f6c634300081c0033" as `0x${string}`;

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
  preMigrationControllerAddress: Address;
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
  minExpiryDays: number;
}

export interface Checkpoint {
  lastProcessedLineNumber: number;
  totalProcessed: number;
  totalExpected: number;
  successCount: number;
  renewedCount: number;
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

export function createFreshCheckpoint(): Checkpoint {
  return {
    lastProcessedLineNumber: -1,
    totalProcessed: 0,
    totalExpected: 0,
    successCount: 0,
    renewedCount: 0,
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

  finishedName(name: string, result: 'registered' | 'renewed' | 'skipped' | 'failed'): void {
    const icon = result === 'registered' ? '✓' : result === 'renewed' ? '↻' : result === 'skipped' ? '⊘' : '✗';
    const color = result === 'registered' ? green : result === 'renewed' ? cyan : result === 'skipped' ? yellow : red;
    this.raw(
      color(`${icon} Done: ${bold(name)}.eth`) + dim(` (${result})`),
      `${icon} Done: ${name}.eth (${result})`
    );
  }

  registering(name: string, expiry: string): void {
    this.raw(
      blue(`  → Registering on v2`) + dim(` (expires: ${expiry})`),
      `  → Registering on v2 (expires: ${expiry})`
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

  renewing(name: string, currentExpiry: string, newExpiry: string): void {
    this.raw(
      blue(`  → Renewing on v2`) +
      dim(` (current: ${currentExpiry}, new: ${newExpiry})`),
      `  → Renewing on v2 (current: ${currentExpiry}, new: ${newExpiry})`
    );
  }

  renewed(tx: string): void {
    this.raw(
      green(`  → ✓ Renewed successfully`) + dim(` (tx: ${tx})`),
      `  → ✓ Renewed successfully (tx: ${tx})`
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
    stats: { registered: number; renewed: number; skipped: number; failed: number }
  ): void {
    const percent = Math.round((current / total) * 100);
    this.raw(
      magenta(
        `Progress: ${bold(`${current}/${total}`)} (${percent}%) - ` +
        `${green("Registered: " + stats.registered)}, ` +
        `${cyan("Renewed: " + stats.renewed)}, ` +
        `${yellow("Skipped: " + stats.skipped)}, ` +
        `${red("Failed: " + stats.failed)}`
      ),
      `Progress: ${current}/${total} (${percent}%) - Registered: ${stats.registered}, Renewed: ${stats.renewed}, Skipped: ${stats.skipped}, Failed: ${stats.failed}`
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

  skippingExpiringSoon(name: string, daysUntilExpiry: number): void {
    this.raw(
      yellow(`  → ⊘ Skipping: ${bold(name)}.eth`) + dim(` (expires in ${daysUntilExpiry} days)`),
      `  → ⊘ Skipping: ${name}.eth (expires in ${daysUntilExpiry} days)`
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

export async function deployBatchRegistrar(
  client: any,
  registryAddress: Address,
  checkpointAddress?: Address
): Promise<{ contract: any; address: Address }> {
  // Check if we can reuse a previously deployed BatchRegistrar from checkpoint
  if (checkpointAddress) {
    const existingCode = await client.getCode({ address: checkpointAddress });
    if (existingCode && existingCode !== "0x") {
      logger.success(`Reusing BatchRegistrar from checkpoint at ${checkpointAddress}`);
      return {
        contract: getContract({
          address: checkpointAddress,
          abi: BATCH_REGISTRAR_ABI,
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
    abi: BATCH_REGISTRAR_ABI,
    bytecode: BATCH_REGISTRAR_BYTECODE,
    args: [registryAddress],
  });

  const receipt = await waitForSuccessfulTransactionReceipt(client, { hash, ensureDeployment: true });
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
      abi: BATCH_REGISTRAR_ABI,
      client,
    }),
    address: deployedAddress,
  };
}

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
    if (parts.length >= 2) {
      const labelName = parts[1].trim();
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

async function fetchAndRegisterInBatches(
  config: PreMigrationConfig,
): Promise<void> {
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

  const client = createWalletClient({
    account: privateKeyToAccount(config.privateKey),
    transport: http(config.rpcUrl, { retryCount: 0, timeout: RPC_TIMEOUT_MS }),
  }).extend(publicActions);

  const registry = getContract({
    address: config.registryAddress,
    abi: PERMISSIONED_REGISTRY_ABI,
    client,
  });

  const mainnetClient = createPublicClient({
    chain: mainnet,
    transport: http(config.mainnetRpcUrl, { retryCount: 3, timeout: RPC_TIMEOUT_MS }),
  });

  const { contract: batchRegistrar, address: batchRegistrarAddress } = await deployBatchRegistrar(
    client,
    config.registryAddress,
    checkpoint.batchRegistrarAddress
  );

  checkpoint.batchRegistrarAddress = batchRegistrarAddress;

  const requiredRoles = ROLES.OWNER.EAC.REGISTRAR | ROLES.OWNER.EAC.RENEW;
  const hasRole = await registry.read.hasRootRoles([
    requiredRoles,
    batchRegistrarAddress,
  ]);

  if (!hasRole) {
    logger.info("Granting REGISTRAR and RENEW roles to BatchRegistrar...");
    const hash = await (registry.write.grantRootRoles as any)([
      requiredRoles,
      batchRegistrarAddress,
    ]);
    await waitForSuccessfulTransactionReceipt(client, { hash });
    logger.success("REGISTRAR and RENEW roles granted to BatchRegistrar");
  } else {
    logger.info("BatchRegistrar already has REGISTRAR and RENEW roles");
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
      checkpoint.totalExpected += batch.length;

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

      logger.info(
        `Batch complete. Total: ${checkpoint.totalProcessed} processed ` +
        `(${checkpoint.successCount} registered, ${checkpoint.renewedCount} renewed, ` +
        `${checkpoint.skippedCount} skipped, ${checkpoint.invalidLabelCount} invalid, ` +
        `${checkpoint.failureCount} failed)`
      );

      if (config.limit && checkpoint.totalProcessed >= config.limit) {
        logger.info(`\nReached limit of ${config.limit} names. Stopping.`);
        break;
      }
    } catch (error) {
      logger.error(`Failed to process batch: ${error}`);
      throw error;
    }
  }

  printFinalSummary(checkpoint);
}

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
  const alreadyRegisteredNames = new Set<string>();
  let lastLineNumber = checkpoint.lastProcessedLineNumber;

  const minExpiryThreshold = BigInt(Math.floor(Date.now() / 1000) + config.minExpiryDays * 86400);

  for (let i = 0; i < registrations.length; i++) {
    const registration = registrations[i];
    const globalIndex = checkpoint.totalProcessed + i + 1;
    lastLineNumber = registration.lineNumber;

    logger.processingName(registration.labelName, globalIndex, checkpoint.totalExpected);

    try {
      let isAlreadyRegistered = false;
      try {
        const [tokenId, entry] = await registry.read.getNameData([registration.labelName]);
        if (entry.expiry > 0n && entry.expiry > BigInt(Math.floor(Date.now() / 1000))) {
          const owner = await registry.read.ownerOf([tokenId]);
          if (owner !== zeroAddress) {
            if (owner.toLowerCase() !== config.preMigrationControllerAddress.toLowerCase()) {
              logger.error(`Name ${registration.labelName}.eth is already registered but owned by unexpected address: ${owner}`);
              checkpoint.failureCount++;
              logger.finishedName(registration.labelName, 'failed');
              continue;
            }
            isAlreadyRegistered = true;
            alreadyRegisteredNames.add(registration.labelName);
          }
        }
      } catch {
        // Name not found - proceed with mainnet verification
      }

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

      if (mainnetResult.expiry <= minExpiryThreshold) {
        const daysUntilExpiry = Number((mainnetResult.expiry - BigInt(Math.floor(Date.now() / 1000))) / 86400n);
        logger.skippingExpiringSoon(registration.labelName, daysUntilExpiry);
        checkpoint.skippedCount++;
        logger.finishedName(registration.labelName, 'skipped');
        continue;
      }

      const expiryDateFormatted = new Date(Number(mainnetResult.expiry) * 1000).toISOString().split('T')[0];
      logger.mainnetVerified(registration.labelName, expiryDateFormatted);

      batchNames.push({
        label: registration.labelName,
        owner: config.preMigrationControllerAddress,
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

    checkpoint.totalProcessed++;
    checkpoint.lastProcessedLineNumber = lastLineNumber;
    checkpoint.timestamp = new Date().toISOString();

    if (!config.disableCheckpoint) {
      saveCheckpoint(checkpoint);
    }
  }

  checkpoint.lastProcessedLineNumber = lastLineNumber;

  if (batchNames.length > 0 && !config.dryRun) {
    logger.info(`\nBatch registering ${batchNames.length} names...`);

    try {
      const hash = await batchRegistrar.write.batchRegister([batchNames]);
      await waitForSuccessfulTransactionReceipt(client, { hash });

      logger.success(`Batch registration successful (tx: ${hash})`);

      for (const name of batchNames) {
        if (alreadyRegisteredNames.has(name.label)) {
          checkpoint.renewedCount++;
          logger.renewed(hash);
          logger.finishedName(name.label, 'renewed');
        } else {
          checkpoint.successCount++;
          logger.registered(hash);
          logger.finishedName(name.label, 'registered');
        }
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

    for (const name of batchNames) {
      logger.dryRun();
      if (alreadyRegisteredNames.has(name.label)) {
        checkpoint.renewedCount++;
        logger.finishedName(name.label, 'renewed');
      } else {
        checkpoint.successCount++;
        logger.finishedName(name.label, 'registered');
      }
    }
  }

  checkpoint.timestamp = new Date().toISOString();

  if (!config.disableCheckpoint) {
    saveCheckpoint(checkpoint);
  }

  return checkpoint;
}

function calculateSuccessRate(successCount: number, totalAttempts: number): number {
  return totalAttempts > 0 ? Math.round((successCount / totalAttempts) * 100) : 0;
}

function printFinalSummary(checkpoint: Checkpoint): void {
  const actualRegistrations = checkpoint.successCount + checkpoint.renewedCount + checkpoint.failureCount;

  logger.info('');
  logger.divider();
  logger.header('Pre-Migration Complete');
  logger.divider();

  logger.config('Total names processed', checkpoint.totalProcessed);
  logger.config('Successfully registered', green(checkpoint.successCount.toString()));
  logger.config('Successfully renewed', cyan(checkpoint.renewedCount.toString()));
  logger.config('Skipped (expiring soon/already up-to-date/expired)', yellow(checkpoint.skippedCount.toString()));
  logger.config('Invalid labels', yellow(checkpoint.invalidLabelCount.toString()));
  logger.config('Failed (other errors)', checkpoint.failureCount > 0 ? red(checkpoint.failureCount.toString()) : checkpoint.failureCount);
  logger.config('Actual registrations/renewals attempted', actualRegistrations);

  const rate = calculateSuccessRate(checkpoint.successCount + checkpoint.renewedCount, actualRegistrations);
  if (actualRegistrations > 0) {
    logger.config('Success rate', `${rate}%`);
  }

  logger.divider();

  if (checkpoint.failureCount > 0) {
    logger.warning(`\nSome registrations failed. Check ${ERROR_LOG_FILE} for details.`);
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
      timeout: RPC_TIMEOUT_MS,
    }),
  }).extend(publicActions);

  const registry = providedRegistry || getContract({
    address: config.registryAddress,
    abi: PERMISSIONED_REGISTRY_ABI,
    client,
  });

  const mainnetClient = createPublicClient({
    chain: mainnet,
    transport: http(config.mainnetRpcUrl, {
      retryCount: 3,
      timeout: RPC_TIMEOUT_MS,
    }),
  });

  const { contract: batchRegistrar, address: batchRegistrarAddress } = await deployBatchRegistrar(
    client,
    config.registryAddress,
    config.batchRegistrarAddress
  );

  const requiredRoles = ROLES.OWNER.EAC.REGISTRAR | ROLES.OWNER.EAC.RENEW;
  const hasRole = await registry.read.hasRootRoles([
    requiredRoles,
    batchRegistrarAddress,
  ]);

  if (!hasRole) {
    const hash = await (registry.write.grantRootRoles as any)([
      requiredRoles,
      batchRegistrarAddress,
    ]);
    await waitForSuccessfulTransactionReceipt(client, { hash });
  }

  let checkpoint: Checkpoint;
  if (config.disableCheckpoint) {
    checkpoint = createFreshCheckpoint();
    checkpoint.totalExpected = registrations.length;
  } else if (config.continue) {
    const loaded = loadCheckpoint();
    if (loaded) {
      checkpoint = {
        ...loaded,
        renewedCount: loaded.renewedCount ?? 0,
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

  await processBatch(
    config,
    registrations,
    client,
    registry,
    batchRegistrar,
    mainnetClient,
    checkpoint
  );

  printFinalSummary(checkpoint);
}

export async function main(argv = process.argv): Promise<void> {
  const program = new Command()
    .name("premigrate")
    .description("Pre-migrate ENS .eth 2LDs from Mainnet to v2. By default starts fresh. Use --continue to resume from checkpoint.")
    .requiredOption("--v2-rpc-url <url>", "V2 RPC endpoint")
    .option("--mainnet-rpc-url <url>", "Mainnet RPC endpoint for verification", "https://mainnet.gateway.tenderly.co/")
    .requiredOption("--v2-registry <address>", "ETH Registry contract address")
    .requiredOption("--pre-migration-controller <address>", "PreMigrationController address")
    .requiredOption("--private-key <key>", "Deployer private key (has REGISTRAR role)")
    .requiredOption("--csv-file <path>", "Path to CSV file containing ENS registrations")
    .option("--batch-size <number>", "Number of names to process per batch", "50")
    .option("--start-index <number>", "Starting index for resuming partial migrations", "0")
    .option("--limit <number>", "Maximum total number of names to process and register")
    .option("--dry-run", "Simulate without executing transactions", false)
    .option("--continue", "Continue from previous checkpoint if it exists", false)
    .option("--min-expiry-days <days>", "Skip names expiring within this many days", "7")
    .option("--role-bitmap <hex>", "Custom role bitmap (hex string) for when registering names");

  program.parse(argv);
  const opts = program.opts();

  const config: PreMigrationConfig = {
    rpcUrl: opts.v2RpcUrl,
    mainnetRpcUrl: opts.mainnetRpcUrl,
    registryAddress: opts.v2Registry as Address,
    preMigrationControllerAddress: opts.preMigrationController as Address,
    privateKey: opts.privateKey as `0x${string}`,
    csvFilePath: opts.csvFile,
    batchSize: parseInt(opts.batchSize) || 100,
    startIndex: parseInt(opts.startIndex) || 0,
    limit: opts.limit ? parseInt(opts.limit) : null,
    dryRun: opts.dryRun,
    continue: opts.continue,
    minExpiryDays: parseInt(opts.minExpiryDays) || 7,
    roleBitmap: opts.roleBitmap ? BigInt(opts.roleBitmap) : ROLES.ALL,
  };

  try {
    logger.header("ENS Pre-Migration Script");
    logger.divider();

    logger.info(`Configuration:`);
    logger.config('V2 RPC URL', config.rpcUrl);
    logger.config('Mainnet RPC URL', config.mainnetRpcUrl);
    logger.config('Registry', config.registryAddress);
    logger.config('PreMigrationController', config.preMigrationControllerAddress);
    logger.config('CSV File', config.csvFilePath);
    logger.config('Batch Size', config.batchSize);
    logger.config('Min Expiry Days', config.minExpiryDays);
    logger.config('Limit', config.limit ?? "none");
    logger.config('Dry Run', config.dryRun);
    logger.config('Continue Mode', config.continue ?? false);
    if (config.continue && loadCheckpoint()) {
      const cp = loadCheckpoint()!;
      const renewedCount = cp.renewedCount ?? 0;
      const invalidCount = cp.invalidLabelCount ?? 0;
      const lastLine = cp.lastProcessedLineNumber ?? -1;
      logger.config('Checkpoint Found', `${cp.totalProcessed} processed (${cp.successCount} registered, ${renewedCount} renewed, ${cp.skippedCount} skipped, ${invalidCount} invalid, ${cp.failureCount} failed) (last line: ${lastLine})`);
      config.startIndex = lastLine;
      logger.info(`Resuming from CSV line ${config.startIndex}`);
    }
    logger.config('Role Bitmap', `0x${config.roleBitmap.toString(16)}`);
    logger.info("");

    await fetchAndRegisterInBatches(config);

    logger.success("\nPre-migration script completed successfully!");
  } catch (error) {
    logger.error(`Fatal error: ${error}`);
    console.error(error);
    process.exit(1);
  }
}

if (import.meta.main) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
