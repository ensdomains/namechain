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
import * as deployFunctions from "@rocketh/deploy"; // this one provide a deploy function
import * as readExecuteFunctions from "@rocketh/read-execute"; // this one provide read,execute functions

// ------------------------------------------------------------------------------------------------
// we re-export the artifacts, so they are easily available from the alias
import artifacts from "./generated/artifacts.js";
export { artifacts };
// ------------------------------------------------------------------------------------------------
// while not necessary, we also converted the execution function type to know about the named accounts
// this way you get type safe accounts
import {
  type Environment as Environment_,
  setup,
  loadAndExecuteDeployments,
} from "rocketh";

import type { Address } from "viem";
type L1Arguments = {
  l2Deploy: {
    deployments: Record<string, { address: Address }>;
  };
  verifierAddress: Address;
};
export type Arguments = L1Arguments | undefined;

const functions = {
  ...deployFunctions,
  ...readExecuteFunctions,
};

const execute = setup<typeof functions, typeof config.accounts>(
  functions,
)<Arguments>;

type Environment = Environment_<typeof config.accounts>;

export { execute, loadAndExecuteDeployments, type Environment };
