import { writeFileSync, rmSync, existsSync } from "node:fs";
import type { Checkpoint, ENSRegistration } from "../../script/preMigration.js";

export function createTestCheckpoint(overrides: Partial<Checkpoint> = {}): Checkpoint {
  return {
    lastProcessedIndex: -1,
    totalProcessed: 0,
    totalExpected: 0,
    successCount: 0,
    failureCount: 0,
    skippedCount: 0,
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

export function createMockRegistration(labelName: string, expiryDate?: string): ENSRegistration {
  const now = Math.floor(Date.now() / 1000);
  return {
    id: `0x${Buffer.from(labelName).toString('hex')}`,
    labelName,
    registrant: "0x1234567890abcdef1234567890abcdef12345678",
    expiryDate: expiryDate || String(now + 31536000), // 1 year from now
    registrationDate: String(now),
    domain: {
      name: `${labelName}.eth`,
      labelhash: `0x${Buffer.from(labelName).toString('hex')}`,
      parent: {
        id: "0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae",
      },
    },
  };
}
