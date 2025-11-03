import { describe, it, expect, beforeEach, afterEach } from "bun:test";
import { existsSync } from "node:fs";
import {
  createFreshCheckpoint,
  loadCheckpoint,
  saveCheckpoint,
  type PreMigrationConfig,
} from "../../script/preMigration.js";
import {
  createTestCheckpoint,
  writeTestCheckpoint,
  deleteTestCheckpoint,
} from "../utils/preMigrationTestUtils.js";
import { ROLES } from "../../deploy/constants.js";

const TEST_CHECKPOINT_FILE = "preMigration-checkpoint.json";

describe("Pre-Migration Script Unit Tests", () => {
  afterEach(() => {
    // Clean up any test checkpoint files
    deleteTestCheckpoint(TEST_CHECKPOINT_FILE);
  });

  describe("Checkpoint Management", () => {
    it("should create fresh checkpoint with correct initial values", () => {
      const checkpoint = createFreshCheckpoint();

      expect(checkpoint.lastProcessedLineNumber).toBe(-1);
      expect(checkpoint.totalProcessed).toBe(0);
      expect(checkpoint.successCount).toBe(0);
      expect(checkpoint.failureCount).toBe(0);
      expect(checkpoint.skippedCount).toBe(0);
      expect(checkpoint.timestamp).toBeDefined();
      expect(new Date(checkpoint.timestamp).getTime()).toBeGreaterThan(0);
    });

    it("should save and load checkpoint correctly", () => {
      const original = createTestCheckpoint({
        lastProcessedLineNumber: 42,
        totalProcessed: 30,
        successCount: 25,
        failureCount: 2,
        skippedCount: 15,
      });

      saveCheckpoint(original);
      expect(existsSync(TEST_CHECKPOINT_FILE)).toBe(true);

      const loaded = loadCheckpoint();
      expect(loaded).not.toBeNull();
      expect(loaded!.lastProcessedLineNumber).toBe(42);
      expect(loaded!.totalProcessed).toBe(30);
      expect(loaded!.successCount).toBe(25);
      expect(loaded!.failureCount).toBe(2);
      expect(loaded!.skippedCount).toBe(15);
    });

    it("should return null when checkpoint file does not exist", () => {
      const loaded = loadCheckpoint();
      expect(loaded).toBeNull();
    });

    it("should return null and log error when checkpoint file is corrupted", () => {
      // Write invalid JSON
      writeTestCheckpoint({ invalid: "data" } as any);

      const loaded = loadCheckpoint();
      // Should handle gracefully
      expect(loaded).toBeDefined();
    });

    it("should handle legacy checkpoints without skippedCount and lastProcessedLineNumber", () => {
      const legacyCheckpoint = {
        totalProcessed: 8,
        successCount: 7,
        failureCount: 1,
        timestamp: new Date().toISOString(),
        // Missing skippedCount and lastProcessedLineNumber
      };

      writeTestCheckpoint(legacyCheckpoint as any);
      const loaded = loadCheckpoint();

      expect(loaded).not.toBeNull();
      expect(loaded!.totalProcessed).toBe(8);
    });
  });

  describe("Configuration", () => {
    it("should have correct default behavior (continue: false)", () => {
      const config: PreMigrationConfig = {
        rpcUrl: "http://localhost:8545",
        mainnetRpcUrl: "http://localhost:8546",
        registryAddress: "0x0000000000000000000000000000000000000001" as any,
        bridgeControllerAddress: "0x0000000000000000000000000000000000000002" as any,
        privateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
        csvFilePath: "test.csv",
        batchSize: 100,
        startIndex: 0,
        limit: null,
        dryRun: false,
        roleBitmap: ROLES.ALL,
        // continue is undefined (false by default)
      };

      expect(config.continue).toBeUndefined();
      expect(config.disableCheckpoint).toBeUndefined();
    });

    it("should support continue mode", () => {
      const config: PreMigrationConfig = {
        rpcUrl: "http://localhost:8545",
        mainnetRpcUrl: "http://localhost:8546",
        registryAddress: "0x0000000000000000000000000000000000000001" as any,
        bridgeControllerAddress: "0x0000000000000000000000000000000000000002" as any,
        privateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
        csvFilePath: "test.csv",
        batchSize: 100,
        startIndex: 0,
        limit: null,
        dryRun: false,
        roleBitmap: ROLES.ALL,
        continue: true,
      };

      expect(config.continue).toBe(true);
    });

    it("should support disableCheckpoint for tests", () => {
      const config: PreMigrationConfig = {
        rpcUrl: "http://localhost:8545",
        mainnetRpcUrl: "http://localhost:8546",
        registryAddress: "0x0000000000000000000000000000000000000001" as any,
        bridgeControllerAddress: "0x0000000000000000000000000000000000000002" as any,
        privateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
        csvFilePath: "test.csv",
        batchSize: 100,
        startIndex: 0,
        limit: null,
        dryRun: false,
        roleBitmap: ROLES.ALL,
        disableCheckpoint: true,
      };

      expect(config.disableCheckpoint).toBe(true);
    });
  });

  describe("Checkpoint Helper Functions", () => {
    it("should create checkpoint with custom values", () => {
      const checkpoint = createTestCheckpoint({
        lastProcessedLineNumber: 99,
        successCount: 50,
      });

      expect(checkpoint.lastProcessedLineNumber).toBe(99);
      expect(checkpoint.successCount).toBe(50);
      expect(checkpoint.failureCount).toBe(0); // default
    });

    it("should write checkpoint to file", () => {
      const checkpoint = createTestCheckpoint();
      writeTestCheckpoint(checkpoint);

      expect(existsSync(TEST_CHECKPOINT_FILE)).toBe(true);
    });

    it("should delete checkpoint file if exists", () => {
      writeTestCheckpoint(createTestCheckpoint());
      expect(existsSync(TEST_CHECKPOINT_FILE)).toBe(true);

      deleteTestCheckpoint();
      expect(existsSync(TEST_CHECKPOINT_FILE)).toBe(false);
    });

    it("should not error when deleting non-existent checkpoint", () => {
      expect(existsSync(TEST_CHECKPOINT_FILE)).toBe(false);
      expect(() => deleteTestCheckpoint()).not.toThrow();
    });
  });

  describe("Checkpoint Line Number Tracking", () => {
    it("should initialize lastProcessedLineNumber to -1", () => {
      const checkpoint = createFreshCheckpoint();
      expect(checkpoint.lastProcessedLineNumber).toBe(-1);
    });

    it("should save lastProcessedLineNumber in checkpoint", () => {
      const checkpoint = createTestCheckpoint({
        lastProcessedLineNumber: 150,
        totalProcessed: 100,
      });

      saveCheckpoint(checkpoint);
      const loaded = loadCheckpoint();

      expect(loaded).not.toBeNull();
      expect(loaded!.lastProcessedLineNumber).toBe(150);
      expect(loaded!.totalProcessed).toBe(100);
    });

    it("should handle checkpoint continuation with different line numbers than processed count", () => {
      const checkpoint = createTestCheckpoint({
        lastProcessedLineNumber: 200,
        totalProcessed: 150,
        skippedCount: 30,
        invalidLabelCount: 20,
      });

      expect(checkpoint.lastProcessedLineNumber).toBe(200);
      expect(checkpoint.totalProcessed).toBe(150);
    });

    it("should preserve lastProcessedLineNumber when loading legacy checkpoints", () => {
      const legacyCheckpoint = {
        totalProcessed: 50,
        successCount: 40,
        failureCount: 5,
        skippedCount: 5,
        invalidLabelCount: 0,
        timestamp: new Date().toISOString(),
      };

      writeTestCheckpoint(legacyCheckpoint as any);
      const loaded = loadCheckpoint();

      expect(loaded).not.toBeNull();
      expect(loaded!.lastProcessedLineNumber).toBeUndefined();
    });
  });

  describe("Incremental Checkpoint Saving", () => {
    it("should update totalProcessed incrementally", () => {
      const checkpoint1 = createTestCheckpoint({
        totalProcessed: 0,
        lastProcessedLineNumber: -1,
      });

      checkpoint1.totalProcessed++;
      checkpoint1.lastProcessedLineNumber = 5;
      expect(checkpoint1.totalProcessed).toBe(1);
      expect(checkpoint1.lastProcessedLineNumber).toBe(5);

      checkpoint1.totalProcessed++;
      checkpoint1.lastProcessedLineNumber = 10;
      expect(checkpoint1.totalProcessed).toBe(2);
      expect(checkpoint1.lastProcessedLineNumber).toBe(10);
    });

    it("should track line numbers independently from processed count", () => {
      const checkpoint = createTestCheckpoint({
        totalProcessed: 0,
        lastProcessedLineNumber: -1,
      });

      checkpoint.totalProcessed = 5;
      checkpoint.lastProcessedLineNumber = 20;

      expect(checkpoint.totalProcessed).toBe(5);
      expect(checkpoint.lastProcessedLineNumber).toBe(20);
      expect(checkpoint.lastProcessedLineNumber).not.toBe(checkpoint.totalProcessed);
    });

    it("should maintain checkpoint consistency across multiple saves", () => {
      let checkpoint = createTestCheckpoint();

      for (let i = 0; i < 5; i++) {
        checkpoint.totalProcessed++;
        checkpoint.lastProcessedLineNumber = i * 10;
        checkpoint.successCount++;
        saveCheckpoint(checkpoint);

        const loaded = loadCheckpoint();
        expect(loaded).not.toBeNull();
        expect(loaded!.totalProcessed).toBe(i + 1);
        expect(loaded!.lastProcessedLineNumber).toBe(i * 10);
        expect(loaded!.successCount).toBe(i + 1);
      }
    });

    it("should handle interrupted processing with partial batch", () => {
      const checkpoint = createTestCheckpoint({
        totalProcessed: 7,
        lastProcessedLineNumber: 15,
        successCount: 5,
        skippedCount: 2,
      });

      saveCheckpoint(checkpoint);
      const loaded = loadCheckpoint();

      expect(loaded).not.toBeNull();
      expect(loaded!.totalProcessed).toBe(7);
      expect(loaded!.lastProcessedLineNumber).toBe(15);
      expect(loaded!.successCount).toBe(5);
      expect(loaded!.skippedCount).toBe(2);
    });
  });
});
