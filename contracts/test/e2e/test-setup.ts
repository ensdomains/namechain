// Global test setup
import { afterAll, beforeEach } from "bun:test";
import { type MockRelay, setupMockRelay } from "../../script/mockRelay.js";
import {
  type CrossChainEnvironment,
  type CrossChainSnapshot,
  setupCrossChainEnvironment,
} from "../../script/setup.js";

declare global {
  // Add CrossChainEnvironment type to NodeJS.ProcessEnv for type safety
  namespace NodeJS {
    interface ProcessEnv {
      TEST_GLOBALS?: {
        env: CrossChainEnvironment;
        relay: MockRelay;
        resetState: CrossChainSnapshot;
        disableStateReset: () => void;
        enableStateReset: () => Promise<void>;
        __canResetState: boolean;
      };
    }
  }
}

const env = await setupCrossChainEnvironment({ extraTime: 10 });
const relay = setupMockRelay(env);

process.env.TEST_GLOBALS = {
  env,
  relay,
  resetState: await env.saveState(),
  disableStateReset: () => {
    process.env.TEST_GLOBALS!.__canResetState = false;
  },
  enableStateReset: async () => {
    process.env.TEST_GLOBALS!.__canResetState = true;
    await process.env.TEST_GLOBALS?.resetState();
  },
  __canResetState: true,
};

beforeEach(async () => {
  if (process.env.TEST_GLOBALS?.__canResetState) {
    await process.env.TEST_GLOBALS?.resetState();
  }
});

afterAll(async () => {
  process.env.TEST_GLOBALS?.relay?.removeListeners();
  await process.env.TEST_GLOBALS?.env?.shutdown();
});
