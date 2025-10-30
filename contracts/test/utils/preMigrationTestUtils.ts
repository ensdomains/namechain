import { writeFileSync, rmSync, existsSync } from "node:fs";
import type { Checkpoint, ENSRegistration } from "../../script/preMigration.js";

export function createTestCheckpoint(overrides: Partial<Checkpoint> = {}): Checkpoint {
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
    ...overrides,
  };
}

export function writeTestCheckpoint(checkpoint: Checkpoint, filename = "preMigration-checkpoint.json"): void {
  writeFileSync(filename, JSON.stringify(checkpoint, null, 2));
}

export function deleteTestCheckpoint(filename = "preMigration-checkpoint.json"): void {
  if (existsSync(filename)) {
    rmSync(filename);
  }
}
