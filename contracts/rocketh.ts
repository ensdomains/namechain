// rocketh.ts
// ------------------------------------------------------------------------------------------------
// Typed Config
// ------------------------------------------------------------------------------------------------
import type { UserConfig } from "rocketh";

export const config = {
  accounts: {
    deployer: {
      default: 0,
    },
    owner: {
      default: 0,
      // admin is DAO on mainnet
      1: "0xFe89cc7aBB2C4183683ab71653C4cdc9B02D44b7",
    },
  },
  networks: {
    // "l1-local": {
    //   scripts: ["deploy/l1", "deploy/shared"],
    //   tags: ["l1", "local"],
    //   rpcUrl: "http://127.0.0.1:8545",
    // },
    // "l2-local": {
    //   scripts: ["deploy/l2", "deploy/shared"],
    //   tags: ["l2", "local"],
    //   rpcUrl: "http://127.0.0.1:8546",
    // },
    mainnet: {
      scripts: ["deploy/l1/universalResolver"],
      tags: ["hasDao"],
    },
    sepolia: {
      scripts: ["deploy/l1/universalResolver"],
      tags: [],
    },
    holesky: {
      scripts: ["deploy/l1/universalResolver"],
      tags: [],
    },
  },
} as const satisfies UserConfig;

// ------------------------------------------------------------------------------------------------
// Imports and Re-exports
// ------------------------------------------------------------------------------------------------
// We regroup all what is needed for the deploy scripts
// so that they just need to import this file
import * as deployFunctions from "@rocketh/deploy";
import * as readExecuteFunctions from "@rocketh/read-execute";
import * as viemFunctions from "@rocketh/viem";

// ------------------------------------------------------------------------------------------------
// we re-export the artifacts, so they are easily available from the alias
import artifacts from "./generated/artifacts.js";
export { artifacts };
// ------------------------------------------------------------------------------------------------

import {
  setup,
  type CurriedFunctions,
  type Environment as Environment_,
} from "rocketh";

const functions = {
  ...deployFunctions,
  ...readExecuteFunctions,
  ...viemFunctions,
  __patchProvider(env: Environment_) {
    // replacement for TransactionHashTracker
    // https://github.com/wighawag/rocketh/blob/main/packages/rocketh/src/environment/providers/TransactionHashTracker.ts
    // still not fixed: https://github.com/wighawag/rocketh/issues/24
    const parent = env.network.provider;
    parent.request = async function (args: any) {
      if (args.method === "eth_getTransactionReceipt") {
        const timeout = Date.now() + 2000;
        for (;;) {
          await new Promise((f) => setTimeout(f, 0));
          const receipt = await parent.provider.request(args).catch(() => {});
          if (receipt) return receipt;
          if (Date.now() > timeout)
            throw new Error(`timeout for receipt: ${args.params[0]}`);
        }
      } else {
        const res = await parent.provider.request(args);
        if (/^eth_send(Raw|)Transaction$/.test(args.method)) {
          parent.transactionHashes?.push(res);
        }
        return res;
      }
    };
  },
};

export type Environment = Environment_<typeof config.accounts> &
  CurriedFunctions<typeof functions>;

const { deployScript, loadAndExecuteDeployments } = setup<
  typeof functions,
  typeof config.accounts
>(functions);

import type { RockethArguments } from "./script/types.ts";

const execute = deployScript<RockethArguments>;

export { execute, loadAndExecuteDeployments };
