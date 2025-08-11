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

    const contractAddressMap = {
      mainnet: "0xED73a03F19e8D849E44a39252d222c6ad5217E1e",
      sepolia: "0x3c85752a5d47DD09D677C645Ff2A938B38fbFEbA",
      holesky: "0x9b37980C10bc0A31Bb61d740De46444853fe2359",
    } as const;

    const args = [
      owner,
      contractAddressMap[
        config.network.name as keyof typeof contractAddressMap
      ],
    ] as const;

    console.log("Proxy args", args);
    await new Promise((resolve) => setTimeout(resolve, 10000));

    await deploy(
      "UpgradableUniversalResolverProxy",
      {
        account: deployer,
        artifact: artifacts.UpgradableUniversalResolverProxy,
        args,
      },
      {
        deterministic: {
          type: "create3",
          salt: "0xdeac7148fb7f566f1fc8c8d6720530de8809f3658cf10141ceee7ba0d45eef85",
        },
      },
    );
  },
  { tags: ["UpgradableUniversalResolverProxy", "l1", "universalResolver"] },
);
