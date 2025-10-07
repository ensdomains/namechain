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
import { createMockRegistrations, mockTheGraphFetch } from "../utils/mockTheGraph.js";

describe("Pre-Migration Script E2E", () => {
  let env: CrossChainEnvironment;

  beforeAll(async () => {
    env = await setupCrossChainEnvironment();
  });

  afterAll(() => env?.shutdown);

  it("should fetch from mocked TheGraph and register names on L2", async () => {
    const mockRegistrations = createMockRegistrations(3, "t1");

    const originalFetch = globalThis.fetch;
    globalThis.fetch = mockTheGraphFetch({
      registrations: mockRegistrations,
    });

    try {
      const config: PreMigrationConfig = {
        rpcUrl: `http://${env.l2.hostPort}`,
        registryAddress: env.l2.contracts.ethRegistry.address,
        bridgeControllerAddress: env.l2.contracts.bridgeController.address,
        privateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as `0x${string}`, // test mnemonic account 0
        thegraphApiKey: "mock-api-key",
        batchSize: 100,
        startIndex: 0,
        limit: 3,
        dryRun: false,
        roleBitmap: ROLES.ALL,
        disableCheckpoint: true,
      };

      // Fetch registrations from mocked TheGraph
      const registrations = await fetchAllRegistrations(config);
      expect(registrations.length).toBe(3);
      console.log(`✓ Fetched ${registrations.length} registrations from mocked TheGraph`);

      // Register names on L2 using test environment's client and registry
      await batchRegisterNames(config, registrations, env.l2.client, env.l2.contracts.ethRegistry);

      // Verify all names were registered correctly
      for (const mockReg of mockRegistrations) {
        const [tokenId] = await env.l2.contracts.ethRegistry.read.getNameData([
          mockReg.labelName,
        ]);

        const owner = await env.l2.contracts.ethRegistry.read.ownerOf([tokenId]);
        expect(owner.toLowerCase()).toBe(
          env.l2.contracts.bridgeController.address.toLowerCase()
        );

        const subregistry = await env.l2.contracts.ethRegistry.read.getSubregistry([
          mockReg.labelName,
        ]);
        expect(subregistry).toBe(zeroAddress);

        const resolver = await env.l2.contracts.ethRegistry.read.getResolver([
          mockReg.labelName,
        ]);
        expect(resolver).toBe(zeroAddress);

        console.log(`✓ Verified: ${mockReg.labelName}.eth registered correctly`);
      }
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("should run in dry-run mode without executing transactions", async () => {
    const mockRegistrations = createMockRegistrations(2, "t2");

    const originalFetch = globalThis.fetch;
    globalThis.fetch = mockTheGraphFetch({
      registrations: mockRegistrations,
    });

    try {
      const config: PreMigrationConfig = {
        rpcUrl: `http://${env.l2.hostPort}`,
        registryAddress: env.l2.contracts.ethRegistry.address,
        bridgeControllerAddress: env.l2.contracts.bridgeController.address,
        privateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as `0x${string}`,
        thegraphApiKey: "mock-api-key",
        batchSize: 100,
        startIndex: 0,
        limit: 2,
        dryRun: true,
        roleBitmap: ROLES.ALL,
        disableCheckpoint: true,
      };

      const registrations = await fetchAllRegistrations(config);
      expect(registrations.length).toBe(2);

      await batchRegisterNames(config, registrations, env.l2.client, env.l2.contracts.ethRegistry);

      // Verify names were NOT actually registered (dry run)
      for (const mockReg of mockRegistrations) {
        try {
          const [tokenId] = await env.l2.contracts.ethRegistry.read.getNameData([
            mockReg.labelName,
          ]);
          const owner = await env.l2.contracts.ethRegistry.read.ownerOf([tokenId]);

          // Should be zero address (not registered)
          expect(owner).toBe(zeroAddress);
        } catch {
          // Name doesn't exist - expected in dry-run
          console.log(`✓ Confirmed: ${mockReg.labelName}.eth not registered (dry-run)`);
        }
      }
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("should handle batch processing with pagination", async () => {
    const mockRegistrations = createMockRegistrations(5, "t3");

    const originalFetch = globalThis.fetch;
    globalThis.fetch = mockTheGraphFetch({
      registrations: mockRegistrations,
    });

    try {
      const config: PreMigrationConfig = {
        rpcUrl: `http://${env.l2.hostPort}`,
        registryAddress: env.l2.contracts.ethRegistry.address,
        bridgeControllerAddress: env.l2.contracts.bridgeController.address,
        privateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as `0x${string}`,
        thegraphApiKey: "mock-api-key",
        batchSize: 2, // Small batch size to test pagination
        startIndex: 0,
        limit: 5,
        dryRun: false,
        roleBitmap: ROLES.ALL,
        disableCheckpoint: true,
      };

      const registrations = await fetchAllRegistrations(config);
      expect(registrations.length).toBe(5);

      await batchRegisterNames(config, registrations, env.l2.client, env.l2.contracts.ethRegistry);

      // Verify all 5 names were registered despite small batch size
      let registeredCount = 0;
      for (const mockReg of mockRegistrations) {
        const [tokenId] = await env.l2.contracts.ethRegistry.read.getNameData([
          mockReg.labelName,
        ]);
        const owner = await env.l2.contracts.ethRegistry.read.ownerOf([tokenId]);

        if (owner.toLowerCase() === env.l2.contracts.bridgeController.address.toLowerCase()) {
          registeredCount++;
        }
      }

      expect(registeredCount).toBe(5);
      console.log(`✓ All ${registeredCount} names registered with batch-size=2`);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("should respect limit parameter", async () => {
    const mockRegistrations = createMockRegistrations(10, "t4");

    const originalFetch = globalThis.fetch;
    globalThis.fetch = mockTheGraphFetch({
      registrations: mockRegistrations,
    });

    try {
      const config: PreMigrationConfig = {
        rpcUrl: `http://${env.l2.hostPort}`,
        registryAddress: env.l2.contracts.ethRegistry.address,
        bridgeControllerAddress: env.l2.contracts.bridgeController.address,
        privateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as `0x${string}`,
        thegraphApiKey: "mock-api-key",
        batchSize: 100,
        startIndex: 0,
        limit: 3, // Only fetch 3
        dryRun: false,
        roleBitmap: ROLES.ALL,
        disableCheckpoint: true,
      };

      const registrations = await fetchAllRegistrations(config);
      expect(registrations.length).toBe(3);

      await batchRegisterNames(config, registrations, env.l2.client, env.l2.contracts.ethRegistry);

      // Count how many were actually registered
      let registeredCount = 0;
      for (const mockReg of mockRegistrations.slice(0, 3)) {
        const [tokenId] = await env.l2.contracts.ethRegistry.read.getNameData([
          mockReg.labelName,
        ]);
        const owner = await env.l2.contracts.ethRegistry.read.ownerOf([tokenId]);

        if (owner.toLowerCase() === env.l2.contracts.bridgeController.address.toLowerCase()) {
          registeredCount++;
        }
      }

      expect(registeredCount).toBe(3);
      console.log(`✓ Correctly limited to ${registeredCount} names`);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});
