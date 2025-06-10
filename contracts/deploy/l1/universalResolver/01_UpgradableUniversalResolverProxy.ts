import { artifacts, execute } from "@rocketh";
import { readFile } from "fs/promises";
import { resolve } from "path";
import type { Abi, Deployment } from "rocketh";
import { getAddress } from "viem";

const __dirname = new URL(".", import.meta.url).pathname;
const deploymentsPath = resolve(
  __dirname,
  "../../../lib/ens-contracts/deployments",
);

export default execute(
  async ({
    deploy,
    config,
    get,
    getOrNull,
    namedAccounts,
    network,
    execute: write,
    read,
  }) => {
    const { deployer, owner } = namedAccounts;

    if (network.tags.local) {
      const universalResolver =
        get<(typeof artifacts.UniversalResolver)["abi"]>("UniversalResolver");
      await deploy("UpgradableUniversalResolverProxy", {
        account: deployer,
        artifact: artifacts.UpgradableUniversalResolverProxy,
        args: [owner, universalResolver.address],
      });
      return;
    }

    const v1UniversalResolverDeployment = await readFile(
      resolve(deploymentsPath, `${config.network.name}/UniversalResolver.json`),
      "utf-8",
    );
    const v1UniversalResolverDeploymentJson = JSON.parse(
      v1UniversalResolverDeployment,
    ) as Deployment<Abi>;

    const currentDeployment = getOrNull<
      (typeof artifacts.UpgradableUniversalResolverProxy)["abi"]
    >("UpgradableUniversalResolverProxy");
    if (currentDeployment && !network.tags.hasDao) {
      const currentImplementation = await read(currentDeployment, {
        functionName: "implementation",
      });
      if (
        getAddress(currentImplementation) !==
        getAddress(v1UniversalResolverDeploymentJson.address)
      ) {
        await write(currentDeployment, {
          functionName: "upgradeTo",
          args: [v1UniversalResolverDeploymentJson.address],
          account: deployer,
        });
      }
      return;
    }

    await deploy("UpgradableUniversalResolverProxy", {
      account: deployer,
      artifact: artifacts.UpgradableUniversalResolverProxy,
      args: [owner, v1UniversalResolverDeploymentJson.address],
    });
  },
  { tags: ["UpgradableUniversalResolverProxy", "l1", "universalResolver"] },
);
