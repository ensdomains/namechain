import { injectCoverage } from "./utils/hardhat-coverage.ts";

// when imported for setupFiles:
// does injection before connect() is called
let saveCoverage: () => Promise<void>;
if (process.env.COVERAGE) {
  saveCoverage = injectCoverage("hardhat");
}

// when imported for globalSetup:
// installs shutdown handler
export async function teardown() {
  await saveCoverage?.();
}
