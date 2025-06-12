import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts }) => {
    const { deployer } = namedAccounts;

    const userRegistryImpl = await deploy("UserRegistryImpl", {
      account: deployer,
      artifact: artifacts.UserRegistry,
    });
    console.log("UserRegistryImpl deployed at", userRegistryImpl.address);
  },
  {
    tags: ["UserRegistryImpl", "l2"],
    dependencies: ["VerifiableFactory", "RegistryDatastore", "SimpleRegistryMetadata"],
  },
);
