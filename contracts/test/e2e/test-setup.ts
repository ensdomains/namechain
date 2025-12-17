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
        setupEnv(onEach?: boolean, init?: () => Promise<void>): unknown;
      };
    }
  }
}

const env = await setupCrossChainEnvironment();
const relay = await setupMockRelay(env);

// save the initial state
const resetInitialState = await env.saveState();

// the state that gets reset on each
let resetEachState: CrossChainSnapshot | undefined = resetInitialState; // default to full reset

// the environment is shared between all tests
process.env.TEST_GLOBALS = {
  env,
  relay,
  setupEnv(onEach = true, init) {
    beforeAll(async () => {
      if (!onEach || init) {
        await resetInitialState();
      }
      resetEachState = onEach ? resetInitialState : undefined;
      if (init) {
        await init();
        if (onEach) {
          resetEachState = await env.saveState();
        }
      }
    });
  },
};

beforeEach(async () => {
  await resetEachState?.();
  console.log(await env.getBlocks().then((v) => v.map((x) => x.timestamp)));
});

afterAll(async () => {
  relay.removeListeners();
  await env.shutdown();
});
