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
        setResetState(mode?: boolean): Promise<void>;
      };
    }
  }
}

const env = await setupCrossChainEnvironment({ extraTime: 10 });
const relay = await setupMockRelay(env);

// save the initial state
const resetInitialState = await env.saveState();

// the state that gets reset on each
let resetState: CrossChainSnapshot | undefined = resetInitialState; // default to full reset

// the environment is shared between all tests
// so at the start of each test file, specific how the reset should work:
//
// beforeAll(async () => {
//    // 1.) to enable reset
//    await setResetState(true);
//
//    // 2.) to disable reset
//    await setResetState(false);
//
//    // 3.) to add a prelude
//    await setResetState(false); // reset
//    // make modifications
//    await setResetState(); // save new checkpoint
// });

process.env.TEST_GLOBALS = {
  env,
  relay,
  async setResetState(mode) {
    if (mode === false) {
      await resetInitialState();
      resetState = undefined;
    } else if (mode === true) {
      resetState = resetInitialState;
    } else {
      resetState = await env.saveState();
    }
  },
};

beforeEach(async () => {
  await resetState?.();
});

afterAll(async () => {
  relay.removeListeners();
  await env.shutdown();
});
