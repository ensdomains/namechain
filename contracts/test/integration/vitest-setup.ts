import { afterAll, beforeAll } from "vitest";
import {
  injectCoverage,
  recordCoverage,
} from "./test-utils/hardhat-coverage.ts";

if (process.env.COVERAGE) {
  injectCoverage();
  let save: () => Promise<void> | undefined;
  beforeAll((suite) => {
    save = recordCoverage(suite.tasks[0].name);
  });
  afterAll(() => save?.());
}
