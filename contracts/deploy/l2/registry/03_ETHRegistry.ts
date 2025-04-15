/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts, get }) => {
    const { deployer } = namedAccounts;

    const datastore =
      get<(typeof artifacts.RegistryDatastore)["abi"]>("RegistryDatastore");
    const metadata = get<(typeof artifacts.BaseUriRegistryMetadata)["abi"]>(
      "BaseUriRegistryMetadata"
    );

    await deploy("ETHRegistry", {
      account: deployer,
      artifact: artifacts.ETHRegistry,
      args: [datastore.address, metadata.address],
    });
  },
  // finally you can pass tags and dependencies
  {
    tags: ["ETHRegistry", "registry", "l2"],
    dependencies: ["RegistryDatastore", "BaseUriRegistryMetadata"],
  }
);
