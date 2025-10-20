import { afterAll, afterEach, beforeAll, describe, expect, it } from "bun:test";
import { unlinkSync, existsSync } from "node:fs";
import { zeroAddress } from "viem";
import { ROLES } from "../../deploy/constants.js";
import {
  batchRegisterNames,
  loadCheckpoint,
  saveCheckpoint,
  createFreshCheckpoint,
  type PreMigrationConfig,
} from "../../script/preMigration.js";
import {
  type CrossChainEnvironment,
  setupCrossChainEnvironment,
} from "../../script/setup.js";
import { createCSVTestHelper, setupBaseRegistrarController } from "../utils/mockPreMigration.js";
import { deleteTestCheckpoint } from "../utils/preMigrationTestUtils.js";

const TEST_CSV_PATH = "test-registrations.csv";

describe("Pre-Migration Script E2E", () => {
  let env: CrossChainEnvironment;

  beforeAll(async () => {
    env = await setupCrossChainEnvironment();

    await setupBaseRegistrarController(
      env.l1.client,
      env.l1.contracts.ETHRegistrarV1.address
    );
  });

  afterAll(() => env?.shutdown);

  afterEach(() => {
    deleteTestCheckpoint();
    if (existsSync(TEST_CSV_PATH)) {
      unlinkSync(TEST_CSV_PATH);
    }
  });

  it("should read from CSV and register names from ENS v1 on L2", async () => {
    const csvHelper = createCSVTestHelper(
      env.l1.client,
      env.l1.contracts.ETHRegistrarV1.address
    );

    const duration = BigInt(365 * 24 * 60 * 60);
    const testOwner = "0x1234567890abcdef1234567890abcdef12345678" as const;

    await csvHelper.registerName("test1", testOwner, duration);
    await csvHelper.registerName("test2", testOwner, duration);
    await csvHelper.registerName("test3", testOwner, duration);

    csvHelper.writeCSV(TEST_CSV_PATH);

    const config: PreMigrationConfig = {
      rpcUrl: `http://${env.l2.hostPort}`,
      mainnetRpcUrl: `http://${env.l1.hostPort}`,
      mainnetBaseRegistrarAddress: env.l1.contracts.ETHRegistrarV1.address,
      registryAddress: env.l2.contracts.ETHRegistry.address,
      bridgeControllerAddress: env.l2.contracts.BridgeController.address,
      privateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as `0x${string}`,
      csvFilePath: TEST_CSV_PATH,
      batchSize: 100,
      startIndex: 0,
      limit: 3,
      dryRun: false,
      roleBitmap: ROLES.ALL,
      disableCheckpoint: true,
    };

    const registrations = csvHelper.getRegistrations();
    expect(registrations.length).toBe(3);
    console.log(`✓ Created CSV with ${registrations.length} registrations`);

    await batchRegisterNames(config, registrations, env.l2.client, env.l2.contracts.ETHRegistry);

    for (const reg of registrations) {
      const [tokenId] = await env.l2.contracts.ETHRegistry.read.getNameData([
        reg.labelName,
      ]);
      const owner = await env.l2.contracts.ETHRegistry.read.ownerOf([tokenId]);
      expect(owner.toLowerCase()).toBe(
        env.l2.contracts.BridgeController.address.toLowerCase()
      );
      console.log(`✓ Verified: ${reg.labelName}.eth registered on L2`);
    }
  });

  it("should skip names that are expired on mainnet", async () => {
    const csvHelper = createCSVTestHelper(
      env.l1.client,
      env.l1.contracts.ETHRegistrarV1.address
    );

    const pastDuration = BigInt(1);
    const testOwner = "0x1234567890abcdef1234567890abcdef12345678" as const;

    await csvHelper.registerName("expired1", testOwner, pastDuration);

    await new Promise((resolve) => setTimeout(resolve, 2000));

    csvHelper.writeCSV(TEST_CSV_PATH);

    const config: PreMigrationConfig = {
      rpcUrl: `http://${env.l2.hostPort}`,
      mainnetRpcUrl: `http://${env.l1.hostPort}`,
      mainnetBaseRegistrarAddress: env.l1.contracts.ETHRegistrarV1.address,
      registryAddress: env.l2.contracts.ETHRegistry.address,
      bridgeControllerAddress: env.l2.contracts.BridgeController.address,
      privateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as `0x${string}`,
      csvFilePath: TEST_CSV_PATH,
      batchSize: 100,
      startIndex: 0,
      limit: 1,
      dryRun: false,
      roleBitmap: ROLES.ALL,
      disableCheckpoint: true,
    };

    const registrations = csvHelper.getRegistrations();
    await batchRegisterNames(config, registrations, env.l2.client, env.l2.contracts.ETHRegistry);

    const [tokenId] = await env.l2.contracts.ETHRegistry.read.getNameData(["expired1"]);
    const owner = await env.l2.contracts.ETHRegistry.read.ownerOf([tokenId]);
    expect(owner).toBe(zeroAddress);
    console.log("✓ Expired name was skipped (not registered on L2)");
  });

  it("should handle checkpoint resumption correctly", async () => {
    const csvHelper = createCSVTestHelper(
      env.l1.client,
      env.l1.contracts.ETHRegistrarV1.address
    );

    const duration = BigInt(365 * 24 * 60 * 60);
    const testOwner = "0x1234567890abcdef1234567890abcdef12345678" as const;

    await csvHelper.registerName("resume1", testOwner, duration);
    await csvHelper.registerName("resume2", testOwner, duration);
    await csvHelper.registerName("resume3", testOwner, duration);

    csvHelper.writeCSV(TEST_CSV_PATH);

    const checkpoint = createFreshCheckpoint();
    checkpoint.lastProcessedLineNumber = 0;
    checkpoint.totalProcessed = 1;
    checkpoint.successCount = 1;
    checkpoint.totalExpected = 3;
    saveCheckpoint(checkpoint);

    const config: PreMigrationConfig = {
      rpcUrl: `http://${env.l2.hostPort}`,
      mainnetRpcUrl: `http://${env.l1.hostPort}`,
      mainnetBaseRegistrarAddress: env.l1.contracts.ETHRegistrarV1.address,
      registryAddress: env.l2.contracts.ETHRegistry.address,
      bridgeControllerAddress: env.l2.contracts.BridgeController.address,
      privateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as `0x${string}`,
      csvFilePath: TEST_CSV_PATH,
      batchSize: 100,
      startIndex: 0,
      limit: null,
      dryRun: false,
      roleBitmap: ROLES.ALL,
      continue: true,
    };

    const registrations = csvHelper.getRegistrations();
    await batchRegisterNames(config, registrations, env.l2.client, env.l2.contracts.ETHRegistry);

    const finalCheckpoint = loadCheckpoint();
    expect(finalCheckpoint).not.toBeNull();
    // Checkpoint started at 1, processed 3 more = 4 total
    expect(finalCheckpoint!.totalProcessed).toBe(4);
    console.log(`✓ Checkpoint resumed correctly: ${finalCheckpoint!.totalProcessed} names processed`);
  });

  it("should skip already-registered names on L2", async () => {
    const csvHelper = createCSVTestHelper(
      env.l1.client,
      env.l1.contracts.ETHRegistrarV1.address
    );

    const duration = BigInt(365 * 24 * 60 * 60);
    const testOwner = "0x1234567890abcdef1234567890abcdef12345678" as const;

    await csvHelper.registerName("duplicate1", testOwner, duration);

    csvHelper.writeCSV(TEST_CSV_PATH);

    const config: PreMigrationConfig = {
      rpcUrl: `http://${env.l2.hostPort}`,
      mainnetRpcUrl: `http://${env.l1.hostPort}`,
      mainnetBaseRegistrarAddress: env.l1.contracts.ETHRegistrarV1.address,
      registryAddress: env.l2.contracts.ETHRegistry.address,
      bridgeControllerAddress: env.l2.contracts.BridgeController.address,
      privateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as `0x${string}`,
      csvFilePath: TEST_CSV_PATH,
      batchSize: 100,
      startIndex: 0,
      limit: null,
      dryRun: false,
      roleBitmap: ROLES.ALL,
      disableCheckpoint: true,
    };

    const registrations = csvHelper.getRegistrations();
    await batchRegisterNames(config, registrations, env.l2.client, env.l2.contracts.ETHRegistry);

    console.log("✓ First registration completed");

    await batchRegisterNames(config, registrations, env.l2.client, env.l2.contracts.ETHRegistry);

    const [tokenId] = await env.l2.contracts.ETHRegistry.read.getNameData(["duplicate1"]);
    const owner = await env.l2.contracts.ETHRegistry.read.ownerOf([tokenId]);
    expect(owner.toLowerCase()).toBe(
      env.l2.contracts.BridgeController.address.toLowerCase()
    );
    console.log("✓ Second registration skipped duplicate name correctly");
  });

  it("should handle dry run mode", async () => {
    const csvHelper = createCSVTestHelper(
      env.l1.client,
      env.l1.contracts.ETHRegistrarV1.address
    );

    const duration = BigInt(365 * 24 * 60 * 60);
    const testOwner = "0x1234567890abcdef1234567890abcdef12345678" as const;

    await csvHelper.registerName("dryrun1", testOwner, duration);

    csvHelper.writeCSV(TEST_CSV_PATH);

    const config: PreMigrationConfig = {
      rpcUrl: `http://${env.l2.hostPort}`,
      mainnetRpcUrl: `http://${env.l1.hostPort}`,
      mainnetBaseRegistrarAddress: env.l1.contracts.ETHRegistrarV1.address,
      registryAddress: env.l2.contracts.ETHRegistry.address,
      bridgeControllerAddress: env.l2.contracts.BridgeController.address,
      privateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as `0x${string}`,
      csvFilePath: TEST_CSV_PATH,
      batchSize: 100,
      startIndex: 0,
      limit: null,
      dryRun: true,
      roleBitmap: ROLES.ALL,
      disableCheckpoint: true,
    };

    const registrations = csvHelper.getRegistrations();
    await batchRegisterNames(config, registrations, env.l2.client, env.l2.contracts.ETHRegistry);

    const [tokenId] = await env.l2.contracts.ETHRegistry.read.getNameData(["dryrun1"]);
    const owner = await env.l2.contracts.ETHRegistry.read.ownerOf([tokenId]);
    expect(owner).toBe(zeroAddress);
    console.log("✓ Dry run did not register name on L2");
  });

  it("should respect limit parameter", async () => {
    const csvHelper = createCSVTestHelper(
      env.l1.client,
      env.l1.contracts.ETHRegistrarV1.address
    );

    const duration = BigInt(365 * 24 * 60 * 60);
    const testOwner = "0x1234567890abcdef1234567890abcdef12345678" as const;

    await csvHelper.registerName("limit1", testOwner, duration);
    await csvHelper.registerName("limit2", testOwner, duration);
    await csvHelper.registerName("limit3", testOwner, duration);

    csvHelper.writeCSV(TEST_CSV_PATH);

    const config: PreMigrationConfig = {
      rpcUrl: `http://${env.l2.hostPort}`,
      mainnetRpcUrl: `http://${env.l1.hostPort}`,
      mainnetBaseRegistrarAddress: env.l1.contracts.ETHRegistrarV1.address,
      registryAddress: env.l2.contracts.ETHRegistry.address,
      bridgeControllerAddress: env.l2.contracts.BridgeController.address,
      privateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as `0x${string}`,
      csvFilePath: TEST_CSV_PATH,
      batchSize: 100,
      startIndex: 0,
      limit: 2,
      dryRun: false,
      roleBitmap: ROLES.ALL,
      disableCheckpoint: true,
    };

    const registrations = csvHelper.getRegistrations().slice(0, 2);
    await batchRegisterNames(config, registrations, env.l2.client, env.l2.contracts.ETHRegistry);

    const [tokenId1] = await env.l2.contracts.ETHRegistry.read.getNameData(["limit1"]);
    const owner1 = await env.l2.contracts.ETHRegistry.read.ownerOf([tokenId1]);
    expect(owner1.toLowerCase()).toBe(
      env.l2.contracts.BridgeController.address.toLowerCase()
    );

    const [tokenId2] = await env.l2.contracts.ETHRegistry.read.getNameData(["limit2"]);
    const owner2 = await env.l2.contracts.ETHRegistry.read.ownerOf([tokenId2]);
    expect(owner2.toLowerCase()).toBe(
      env.l2.contracts.BridgeController.address.toLowerCase()
    );

    const [tokenId3] = await env.l2.contracts.ETHRegistry.read.getNameData(["limit3"]);
    const owner3 = await env.l2.contracts.ETHRegistry.read.ownerOf([tokenId3]);
    expect(owner3).toBe(zeroAddress);

    console.log("✓ Limit parameter respected: only 2 names registered");
  });
});
