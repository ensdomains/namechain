import { artifacts, execute } from "@rocketh";
import { labelhash } from "viem";
import { MAX_EXPIRY, ROLES } from "../constants.js";

// TODO: ownership
export default execute(
  async ({ deploy, execute: write, read, get, namedAccounts: { deployer } }) => {
    const rootRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("RootRegistry");

    const registryDatastore =
      get<(typeof artifacts.RegistryDatastore)["abi"]>("RegistryDatastore");

    const hcaFactory =
      get<(typeof artifacts.MockHCAFactoryBasic)["abi"]>("HCAFactory");

    const registryMetadata = get<
      (typeof artifacts.SimpleRegistryMetadata)["abi"]
    >("SimpleRegistryMetadata");

    const ethRegistry = await deploy("ETHRegistry", {
      account: deployer,
      artifact: artifacts.PermissionedRegistry,
      args: [
        registryDatastore.address,
        hcaFactory.address,
        registryMetadata.address,
        deployer,
        ROLES.ALL,
      ],
    });

    const entry = await read(rootRegistry, {
      functionName: 'getEntry',
      args: [BigInt(labelhash('eth'))],
    });

    if (entry.expiry !== 0n) {

        // set subregistry
      await write(rootRegistry, {
        account: deployer,
        functionName: "setSubregistry",
        args: [BigInt(labelhash('eth')), ethRegistry.address],
      });

      // set resolver
      await write(rootRegistry, {
        account: deployer,
        functionName: "setResolver",
        args: [BigInt(labelhash('eth')), ethTLDResolver.address],
      });
    } else {

      await write(rootRegistry, {
        account: deployer,
        functionName: "register",
        args: [
          "eth",
          deployer, 
          ethRegistry.address,
          ethTLDResolver.address,
          0n,
          MAX_EXPIRY,
        ],
      });
    }

  },
  {
    tags: ["ETHRegistry", "l1"],
    dependencies: [
      "RootRegistry",
      "RegistryDatastore",
      "HCAFactory",
      "RegistryMetadata",
    ],
  },
);
