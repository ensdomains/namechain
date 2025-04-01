// rocketh.ts
// ------------------------------------------------------------------------------------------------
// Typed Config
// ------------------------------------------------------------------------------------------------
import { UserConfig } from "rocketh";
export const config = {
  accounts: {
    deployer: {
      default: 0,
    },
    admin: {
      default: 1,
    },
  },
  networks: {
    "l1-local": {
      scripts: ["deploy/l1", "deploy/shared"],
      tags: ["l1"],
    },
    "l2-local": {
      scripts: ["deploy/l2", "deploy/shared"],
      tags: ["l2"],
    },
  },
} as const satisfies UserConfig;

// ------------------------------------------------------------------------------------------------
// Imports and Re-exports
// ------------------------------------------------------------------------------------------------
// We regroup all what is needed for the deploy scripts
// so that they just need to import this file
import "@rocketh/deploy"; // provides the deploy function
import "@rocketh/read-execute"; // provides read, execute functions
// ------------------------------------------------------------------------------------------------
// we re-export the artifacts, so they are easily available from the alias
import artifacts from "./generated/artifacts.js";
export { artifacts };
// ------------------------------------------------------------------------------------------------
// while not necessary, we also converted the execution function type to know about the named accounts
// this way you get type safe accounts
import {
  execute as _execute,
  loadAndExecuteDeployments,
  type NamedAccountExecuteFunction,
} from "rocketh";
const execute = _execute as NamedAccountExecuteFunction<typeof config.accounts>;
export { execute, loadAndExecuteDeployments };
