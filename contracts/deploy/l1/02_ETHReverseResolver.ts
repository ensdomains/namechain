import { artifacts, execute } from "@rocketh";
import { labelhash, zeroAddress } from "viem";
import { MAX_EXPIRY } from "../constants.js";

// TODO: ownership
export default execute(
  async ({
    deploy,
    execute: write,
    read,
    get,
    getV1,
    namedAccounts: { deployer },
  }) => {
    const ensRegistryV1 =
      getV1<(typeof artifacts.ENSRegistry)["abi"]>("ENSRegistry");

    const defaultReverseRegistrarV1 = getV1<
      (typeof artifacts.DefaultReverseRegistrar)["abi"]
    >("DefaultReverseRegistrar");

    const reverseRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ReverseRegistry");

    const ethReverseRegistrar = get<
      (typeof artifacts.StandaloneReverseRegistrar)["abi"]
    >("ETHReverseRegistrar");

    // create resolver for "addr.reverse"
    const ethReverseResolver = await deploy("ETHReverseResolver", {
      account: deployer,
      artifact: artifacts.ETHReverseResolver,
      args: [
        ensRegistryV1.address,
        ethReverseRegistrar.address,
        defaultReverseRegistrarV1.address,
      ],
    });

    const entry = await read(reverseRegistry, {
      functionName: 'getEntry',
      args: [BigInt(labelhash('addr'))],
    });

    if (entry.expiry !== 0n) {

        // set subregistry
      await write(reverseRegistry, {
        account: deployer,
        functionName: "setSubregistry",
        args: [BigInt(labelhash('addr')), zeroAddress],
      });

      // set resolver
      await write(reverseRegistry, {
        account: deployer,
        functionName: "setResolver",
        args: [BigInt(labelhash('addr')), ethReverseResolver.address],
      });
    } else {
      // register "addr.reverse"
    await write(reverseRegistry, {
      account: deployer,
      functionName: "register",
      args: [
        "addr",
        deployer,
        zeroAddress,
        ethReverseResolver.address,
        0n,
        MAX_EXPIRY,
      ],
    });
    }
  },
  {
    tags: ["ETHReverseResolver", "l1"],
    dependencies: [
      "ENSRegistry",
      "ReverseRegistry", // "RootRegistry"
      "DefaultReverseRegistrar",
      "ETHReverseRegistrar",
    ],
  },
);
