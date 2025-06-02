/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";
import { maxUint256 } from "viem";

const ALL_ROLES = maxUint256;

export default execute(
  async ({ deploy, namedAccounts, get }) => {
    const { deployer } = namedAccounts;

    const registryDatastore =
      get<(typeof artifacts.RegistryDatastore)["abi"]>("RegistryDatastore");
    const registryMetadata = get<
      (typeof artifacts.SimpleRegistryMetadata)["abi"]
    >("SimpleRegistryMetadata");

    await deploy("RootRegistry", {
      account: deployer,
      artifact: artifacts.PermissionedRegistry,
      args: [registryDatastore.address, registryMetadata.address, ALL_ROLES],
    });
  },
  // finally you can pass tags and dependencies
  {
    tags: ["RootRegistry", "l1"],
    dependencies: ["RegistryDatastore", "RegistryMetadata"],
  },
);
