import { afterAll } from "vitest";
import { injectCoverage } from "./utils/hardhat-coverage.ts";

if (process.env.COVERAGE) {
  const saveCoverage = injectCoverage("hardhat");
  afterAll(() => saveCoverage());
}
