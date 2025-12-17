// Global test setup
import { afterAll, beforeAll, beforeEach } from "bun:test";
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
        resetInitialState: CrossChainSnapshot;
        setupEnv(options: {
          resetOnEach: boolean;
          initialize?: () => Promise<unknown>;
        }): void;
      };
    }
  }
}

const t0 = Date.now();

const env = await setupCrossChainEnvironment();
const relay = await setupMockRelay(env);

// save the initial state
const resetInitialState = await env.saveState();

console.log(new Date(), `Ready! <${Date.now() - t0}ms>`);

// the state that gets reset on each
let resetEachState: CrossChainSnapshot | undefined = resetInitialState; // default to full reset

// the environment is shared between all tests
process.env.TEST_GLOBALS = {
  env,
  relay,
  resetInitialState,
  setupEnv({ resetOnEach, initialize }) {
    beforeAll(async () => {
      if (!resetOnEach || initialize) {
        await resetInitialState();
      }
      resetEachState = resetOnEach ? resetInitialState : undefined;
      if (initialize) {
        await initialize();
        if (resetOnEach) {
          resetEachState = await env.saveState();
        }
      }
      if (!resetOnEach) {
        await env.sync();
      }
    });
  },
};

beforeEach(async () => {
  await resetEachState?.();
  if (resetEachState) {
    await env.sync();
  }
});

afterAll(async () => {
  relay.removeListeners();
  await env.shutdown();
});
