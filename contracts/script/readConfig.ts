import type {
  Config,
  ConfigOptions,
  UnresolvedNetworkSpecificData,
  UnresolvedUnknownNamedAccounts,
  UserConfig,
} from "rocketh";
import { config } from "../rocketh.js";

export async function readConfig<
  NamedAccounts extends UnresolvedUnknownNamedAccounts = typeof config.accounts,
  Data extends UnresolvedNetworkSpecificData = UnresolvedNetworkSpecificData,
>(options: ConfigOptions): Promise<Config<NamedAccounts, Data>> {
  const configFile = config as unknown as UserConfig<NamedAccounts, Data>;
  if (configFile) {
    if (!options.deployments && configFile.deployments) {
      options.deployments = configFile.deployments;
    }
    if (!options.scripts && configFile.scripts) {
      options.scripts = configFile.scripts;
    }
  }
  const fromEnv = process.env["ETH_NODE_URI_" + options.network];
  const fork = typeof options.network !== "string";
  let networkName = "memory";
  if (options.network) {
    if (typeof options.network === "string") {
      networkName = options.network;
    } else if ("fork" in options.network) {
      networkName = options.network.fork;
    }
  }
  let defaultTags: string[] = [];
  let networkTags =
    (configFile?.networks &&
      (configFile?.networks[networkName]?.tags ||
        configFile?.networks["default"]?.tags)) ||
    defaultTags;
  let networkScripts =
    (configFile?.networks &&
      (configFile?.networks[networkName]?.scripts ||
        configFile?.networks["default"]?.scripts)) ||
    undefined;
  // no default for publicInfo
  const publicInfo = configFile?.networks
    ? configFile?.networks[networkName]?.publicInfo
    : undefined;
  const deterministicDeployment =
    configFile?.networks?.[networkName]?.deterministicDeployment;
  if (!options.provider) {
    let nodeUrl;
    if (typeof fromEnv === "string") {
      nodeUrl = fromEnv;
    } else {
      if (configFile) {
        const network = configFile.networks && configFile.networks[networkName];
        if (network && network.rpcUrl) {
          nodeUrl = network.rpcUrl;
        } else {
          if (options?.ignoreMissingRPC) {
            nodeUrl = "";
          } else {
            if (options.network === "localhost") {
              nodeUrl = "http://127.0.0.1:8545";
            } else {
              console.error(
                `network "${options.network}" is not configured. Please add it to the rocketh.js/ts file`,
              );
              process.exit(1);
            }
          }
        }
      } else {
        if (options?.ignoreMissingRPC) {
          nodeUrl = "";
        } else {
          if (options.network === "localhost") {
            nodeUrl = "http://127.0.0.1:8545";
          } else {
            console.error(
              `network "${options.network}" is not configured. Please add it to the rocketh.js/ts file`,
            );
            process.exit(1);
          }
        }
      }
    }
    return {
      network: {
        nodeUrl,
        name: networkName,
        tags: networkTags,
        fork,
        deterministicDeployment,
        scripts: networkScripts,
        publicInfo,
      },
      deployments: options.deployments,
      saveDeployments: options.saveDeployments,
      scripts: options.scripts,
      data: configFile?.data,
      tags:
        typeof options.tags === "undefined"
          ? undefined
          : options.tags.split(","),
      logLevel: options.logLevel,
      askBeforeProceeding: options.askBeforeProceeding,
      reportGasUse: options.reportGasUse,
      accounts: configFile?.accounts,
    };
  } else {
    return {
      network: {
        provider: options.provider,
        name: networkName,
        tags: networkTags,
        fork,
        deterministicDeployment,
        scripts: networkScripts,
        publicInfo,
      },
      deployments: options.deployments,
      saveDeployments: options.saveDeployments,
      scripts: options.scripts,
      data: configFile?.data,
      tags:
        typeof options.tags === "undefined"
          ? undefined
          : options.tags.split(","),
      logLevel: options.logLevel,
      askBeforeProceeding: options.askBeforeProceeding,
      reportGasUse: options.reportGasUse,
      accounts: configFile?.accounts,
    };
  }
}
