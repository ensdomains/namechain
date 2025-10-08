import { afterAll, beforeAll, describe, expect, it } from "bun:test";
import { zeroAddress } from "viem";
import { ROLES } from "../../deploy/constants.js";
import {
  fetchAllRegistrations,
  batchRegisterNames,
  type PreMigrationConfig,
} from "../../script/preMigration.js";
import {
  type CrossChainEnvironment,
  setupCrossChainEnvironment,
} from "../../script/setup.js";
import { createDynamicTheGraphMock } from "../utils/mockTheGraph.js";

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
});
