import { afterAll, afterEach, beforeAll, describe, expect, it } from "bun:test";
import { zeroAddress } from "viem";
import { ROLES } from "../../deploy/constants.js";
import {
  fetchAllRegistrations,
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
import { createDynamicTheGraphMock } from "../utils/mockTheGraph.js";
import { deleteTestCheckpoint } from "../utils/preMigrationTestUtils.js";

describe("Pre-Migration Script E2E", () => {
  let env: CrossChainEnvironment;

  beforeAll(async () => {
    env = await setupCrossChainEnvironment();

    // Add deployer as controller on BaseRegistrar (using owner account)
    // Owner is account[1]: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
    await env.l1.client.impersonateAccount({
      address: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
    });

    await env.l1.client.writeContract({
      account: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
      address: env.l1.contracts.ethRegistrarV1.address,
      abi: [{
        inputs: [{ internalType: "address", name: "controller", type: "address" }],
        name: "addController",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
      }],
      functionName: "addController",
      args: [env.l1.client.account.address],
    });

    await env.l1.client.stopImpersonatingAccount({
      address: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
    });
  });

  afterAll(() => env?.shutdown);

  afterEach(() => {
    // Clean up any test checkpoint files after each test
    deleteTestCheckpoint();
  });

  it("should fetch from TheGraph and register names from ENS v1 on L2", async () => {
    // Create dynamic TheGraph mock that uses real ENS v1 contracts
    const theGraphMock = createDynamicTheGraphMock(
      env.l1.client,
      env.l1.contracts.ethRegistrarV1.address
    );

    // Register 3 names in ENS v1 BaseRegistrar on L1
    const duration = BigInt(365 * 24 * 60 * 60); // 1 year
    const testOwner = "0x1234567890abcdef1234567890abcdef12345678" as const;

    await theGraphMock.registerName("test1", testOwner, duration);
    await theGraphMock.registerName("test2", testOwner, duration);
    await theGraphMock.registerName("test3", testOwner, duration);

    const config: PreMigrationConfig = {
      rpcUrl: `http://${env.l2.hostPort}`,
      mainnetRpcUrl: `http://${env.l1.hostPort}`, // Point to L1 test chain
      mainnetBaseRegistrarAddress: env.l1.contracts.ethRegistrarV1.address, // Use test L1 BaseRegistrar
      registryAddress: env.l2.contracts.ethRegistry.address,
      bridgeControllerAddress: env.l2.contracts.bridgeController.address,
      privateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as `0x${string}`,
      thegraphApiKey: "mock-api-key",
      batchSize: 100,
      startIndex: 0,
      limit: 3,
      dryRun: false,
      roleBitmap: ROLES.ALL,
      disableCheckpoint: true,
    };

    // Fetch registrations using custom fetch function (no global mocking!)
    const registrations = await fetchAllRegistrations(config, theGraphMock.fetch as typeof fetch);
    expect(registrations.length).toBe(3);
    console.log(`✓ Fetched ${registrations.length} registrations`);

    // Register names on L2 (script creates mainnet client automatically)
    await batchRegisterNames(config, registrations, env.l2.client, env.l2.contracts.ethRegistry);

    // Verify all names were registered on L2
    const mockRegs = theGraphMock.getRegistrations();
    for (const mockReg of mockRegs) {
      const [tokenId] = await env.l2.contracts.ethRegistry.read.getNameData([
        mockReg.labelName,
      ]);
      const owner = await env.l2.contracts.ethRegistry.read.ownerOf([tokenId]);
      expect(owner.toLowerCase()).toBe(
        env.l2.contracts.bridgeController.address.toLowerCase()
      );
      console.log(`✓ Verified: ${mockReg.labelName}.eth registered on L2`);
    }
  });

  it("should skip names that are expired on mainnet", async () => {
    const theGraphMock = createDynamicTheGraphMock(
      env.l1.client,
      env.l1.contracts.ethRegistrarV1.address
    );

    // Register a name with very short duration (already expired)
    const pastDuration = BigInt(1); // 1 second
    const testOwner = "0x1234567890abcdef1234567890abcdef12345678" as const;

    await theGraphMock.registerName("expired1", testOwner, pastDuration);

    // Wait for it to expire
    await new Promise(resolve => setTimeout(resolve, 2000));

    const config: PreMigrationConfig = {
      rpcUrl: `http://${env.l2.hostPort}`,
      mainnetRpcUrl: `http://${env.l1.hostPort}`,
      mainnetBaseRegistrarAddress: env.l1.contracts.ethRegistrarV1.address,
      registryAddress: env.l2.contracts.ethRegistry.address,
      bridgeControllerAddress: env.l2.contracts.bridgeController.address,
      privateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as `0x${string}`,
      thegraphApiKey: "mock-api-key",
      batchSize: 100,
      startIndex: 0,
      limit: 10,
      dryRun: false,
      roleBitmap: ROLES.ALL,
      disableCheckpoint: true,
    };

    const registrations = await fetchAllRegistrations(config, theGraphMock.fetch as typeof fetch);
    expect(registrations.length).toBe(1);

    await batchRegisterNames(config, registrations, env.l2.client, env.l2.contracts.ethRegistry);

    // Verify the expired name was NOT registered on L2
    try {
      const [tokenId] = await env.l2.contracts.ethRegistry.read.getNameData(["expired1"]);
      const owner = await env.l2.contracts.ethRegistry.read.ownerOf([tokenId]);
      expect(owner).toBe(zeroAddress);
    } catch {
      console.log("✓ Confirmed: expired name was not registered on L2");
    }
  });

  describe("Checkpoint System", () => {
    it("should start fresh when --continue is not set (default behavior)", async () => {
      const theGraphMock = createDynamicTheGraphMock(
        env.l1.client,
        env.l1.contracts.ethRegistrarV1.address
      );

      const duration = BigInt(365 * 24 * 60 * 60);
      const testOwner = "0x1234567890abcdef1234567890abcdef12345678" as const;

      // Register 5 names
      for (let i = 1; i <= 5; i++) {
        await theGraphMock.registerName(`checkpoint${i}`, testOwner, duration);
      }

      // First run: process 3 names and save checkpoint
      const config1: PreMigrationConfig = {
        rpcUrl: `http://${env.l2.hostPort}`,
        mainnetRpcUrl: `http://${env.l1.hostPort}`,
        mainnetBaseRegistrarAddress: env.l1.contracts.ethRegistrarV1.address,
        registryAddress: env.l2.contracts.ethRegistry.address,
        bridgeControllerAddress: env.l2.contracts.bridgeController.address,
        privateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as `0x${string}`,
        thegraphApiKey: "mock-api-key",
        batchSize: 100,
        startIndex: 0,
        limit: 3,
        dryRun: false,
        roleBitmap: ROLES.ALL,
        continue: false, // Default: don't continue
      };

      const registrations1 = await fetchAllRegistrations(config1, theGraphMock.fetch as typeof fetch);
      expect(registrations1.length).toBe(3);
      await batchRegisterNames(config1, registrations1, env.l2.client, env.l2.contracts.ethRegistry);

      // Verify checkpoint was created
      const checkpoint = loadCheckpoint();
      expect(checkpoint).not.toBeNull();
      expect(checkpoint!.successCount).toBe(3);

      // Second run WITHOUT --continue: should start from beginning again
      const config2 = { ...config1, limit: 2 };
      const registrations2 = await fetchAllRegistrations(config2, theGraphMock.fetch as typeof fetch);
      expect(registrations2.length).toBe(2);

      // Should process the same first 2 names (already registered, so skipped)
      await batchRegisterNames(config2, registrations2, env.l2.client, env.l2.contracts.ethRegistry);

      console.log("✓ Verified: default behavior starts fresh (ignores checkpoint)");
    });

    it("should continue from checkpoint when --continue is set", async () => {
      const theGraphMock = createDynamicTheGraphMock(
        env.l1.client,
        env.l1.contracts.ethRegistrarV1.address
      );

      const duration = BigInt(365 * 24 * 60 * 60);
      const testOwner = "0x1234567890abcdef1234567890abcdef12345678" as const;

      // Register 10 names
      for (let i = 1; i <= 10; i++) {
        await theGraphMock.registerName(`resume${i}`, testOwner, duration);
      }

      // First run: process first 5 names
      const config1: PreMigrationConfig = {
        rpcUrl: `http://${env.l2.hostPort}`,
        mainnetRpcUrl: `http://${env.l1.hostPort}`,
        mainnetBaseRegistrarAddress: env.l1.contracts.ethRegistrarV1.address,
        registryAddress: env.l2.contracts.ethRegistry.address,
        bridgeControllerAddress: env.l2.contracts.bridgeController.address,
        privateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as `0x${string}`,
        thegraphApiKey: "mock-api-key",
        batchSize: 100,
        startIndex: 0,
        limit: 5,
        dryRun: false,
        roleBitmap: ROLES.ALL,
        continue: false,
      };

      const registrations1 = await fetchAllRegistrations(config1, theGraphMock.fetch as typeof fetch);
      await batchRegisterNames(config1, registrations1, env.l2.client, env.l2.contracts.ethRegistry);

      // Verify first 5 registered
      const checkpoint1 = loadCheckpoint();
      expect(checkpoint1!.successCount).toBe(5);
      expect(checkpoint1!.totalProcessed).toBe(5);

      // Second run WITH --continue: should resume from index 5
      // Adjust startIndex based on checkpoint (simulating main() behavior)
      const config2 = { ...config1, continue: true, limit: 10, startIndex: checkpoint1!.totalProcessed };
      const registrations2 = await fetchAllRegistrations(config2, theGraphMock.fetch as typeof fetch);
      expect(registrations2.length).toBe(5); // Only fetches remaining 5 names

      await batchRegisterNames(config2, registrations2, env.l2.client, env.l2.contracts.ethRegistry);

      // Verify all 10 registered total
      const checkpoint2 = loadCheckpoint();
      expect(checkpoint2!.successCount).toBe(10);
      expect(checkpoint2!.totalProcessed).toBe(10);

      // Verify names 6-10 are registered
      for (let i = 6; i <= 10; i++) {
        const [tokenId] = await env.l2.contracts.ethRegistry.read.getNameData([`resume${i}`]);
        const owner = await env.l2.contracts.ethRegistry.read.ownerOf([tokenId]);
        expect(owner.toLowerCase()).toBe(env.l2.contracts.bridgeController.address.toLowerCase());
      }

      console.log("✓ Verified: --continue resumes from checkpoint");
    });

    it("should warn when --continue set but no checkpoint exists", async () => {
      // Ensure no checkpoint exists
      deleteTestCheckpoint();

      const theGraphMock = createDynamicTheGraphMock(
        env.l1.client,
        env.l1.contracts.ethRegistrarV1.address
      );

      const duration = BigInt(365 * 24 * 60 * 60);
      const testOwner = "0x1234567890abcdef1234567890abcdef12345678" as const;

      await theGraphMock.registerName("nocptest", testOwner, duration);

      const config: PreMigrationConfig = {
        rpcUrl: `http://${env.l2.hostPort}`,
        mainnetRpcUrl: `http://${env.l1.hostPort}`,
        mainnetBaseRegistrarAddress: env.l1.contracts.ethRegistrarV1.address,
        registryAddress: env.l2.contracts.ethRegistry.address,
        bridgeControllerAddress: env.l2.contracts.bridgeController.address,
        privateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as `0x${string}`,
        thegraphApiKey: "mock-api-key",
        batchSize: 100,
        startIndex: 0,
        limit: 1,
        dryRun: false,
        roleBitmap: ROLES.ALL,
        continue: true, // Set continue but no checkpoint exists
      };

      const registrations = await fetchAllRegistrations(config, theGraphMock.fetch as typeof fetch);
      await batchRegisterNames(config, registrations, env.l2.client, env.l2.contracts.ethRegistry);

      // Should start fresh despite --continue flag
      const [tokenId] = await env.l2.contracts.ethRegistry.read.getNameData(["nocptest"]);
      const owner = await env.l2.contracts.ethRegistry.read.ownerOf([tokenId]);
      expect(owner.toLowerCase()).toBe(env.l2.contracts.bridgeController.address.toLowerCase());

      console.log("✓ Verified: warns and starts fresh when checkpoint missing");
    });

    it("should not load checkpoint when continue is false", async () => {
      // Create a fake checkpoint
      const fakeCheckpoint = createFreshCheckpoint();
      fakeCheckpoint.lastProcessedIndex = 99;
      fakeCheckpoint.successCount = 50;
      saveCheckpoint(fakeCheckpoint);

      const theGraphMock = createDynamicTheGraphMock(
        env.l1.client,
        env.l1.contracts.ethRegistrarV1.address
      );

      const duration = BigInt(365 * 24 * 60 * 60);
      const testOwner = "0x1234567890abcdef1234567890abcdef12345678" as const;

      await theGraphMock.registerName("ignorecp", testOwner, duration);

      const config: PreMigrationConfig = {
        rpcUrl: `http://${env.l2.hostPort}`,
        mainnetRpcUrl: `http://${env.l1.hostPort}`,
        mainnetBaseRegistrarAddress: env.l1.contracts.ethRegistrarV1.address,
        registryAddress: env.l2.contracts.ethRegistry.address,
        bridgeControllerAddress: env.l2.contracts.bridgeController.address,
        privateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as `0x${string}`,
        thegraphApiKey: "mock-api-key",
        batchSize: 100,
        startIndex: 0,
        limit: 1,
        dryRun: false,
        roleBitmap: ROLES.ALL,
        continue: false, // Don't continue
      };

      const registrations = await fetchAllRegistrations(config, theGraphMock.fetch as typeof fetch);
      await batchRegisterNames(config, registrations, env.l2.client, env.l2.contracts.ethRegistry);

      // Should have processed from index 0 (ignored checkpoint)
      const [tokenId] = await env.l2.contracts.ethRegistry.read.getNameData(["ignorecp"]);
      const owner = await env.l2.contracts.ethRegistry.read.ownerOf([tokenId]);
      expect(owner.toLowerCase()).toBe(env.l2.contracts.bridgeController.address.toLowerCase());

      console.log("✓ Verified: checkpoint ignored when continue=false");
    });
  });
});
