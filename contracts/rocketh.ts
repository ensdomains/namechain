// rocketh.ts
// ------------------------------------------------------------------------------------------------
// Typed Config
// ------------------------------------------------------------------------------------------------
import { resolve } from "path";
import type { Deployment, UnknownDeployments, UserConfig } from "rocketh";
import type { Abi } from "viem";
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
    sepoliaFresh: {
      scripts: [
        "lib/ens-contracts/deploy",
        "deploy/l1",
        "deploy/l2",
        "deploy/shared",
      ],
      tags: ["l1", "l2", "use_root", "allow_unsafe", "legacy"],
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
  loadDeployments,
  setup,
  type CurriedFunctions,
  type Environment as Environment_,
} from "rocketh";

const deploymentsCache = new Map<string, UnknownDeployments>();

const functions = {
  ...deployFunctions,
  ...readExecuteFunctions,
  ...viemFunctions,
  getV1: (env: Environment_) => {
    const path = resolve(env.config.deployments, "v1");
    const deployments = (() => {
      if (deploymentsCache.has(path)) return deploymentsCache.get(path)!;
      const { deployments: deployments_ } = loadDeployments(
        path,
        env.config.network.name,
        false,
      );
      deploymentsCache.set(path, deployments_);
      return deployments_;
    })();
    return <TAbi extends Abi>(name: string): Deployment<TAbi> => {
      const deployment = deployments[name];
      if (!deployment) throw new Error(`V1 Deployment ${name} not found`);
      return deployment as Deployment<TAbi>;
    };
  },
};

export type Environment = Environment_<typeof config.accounts> &
  CurriedFunctions<typeof functions>;

const enhanced = setup<typeof functions, typeof config.accounts>(functions);

import type { RockethArguments } from "./script/types.ts";

export const execute = enhanced.deployScript<RockethArguments>;
export const deployScript = enhanced.deployScript<RockethArguments>;

export const loadAndExecuteDeployments =
  enhanced.loadAndExecuteDeployments<RockethArguments>;
