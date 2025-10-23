import { artifacts, execute } from "@rocketh";
import { zeroAddress } from "viem";
import { MAX_EXPIRY } from "../constants.js";
import { coinTypeFromChain } from "../../test/utils/resolutions.ts";

export default execute(
  async (
    { deploy, execute: write, get, namedAccounts: { deployer, owner } },
    args,
  ) => {
    if (!args?.l2Deploy) {
      console.log("Skipping NamechainReverseResolver: no L2 deployment");
      return;
    }

    const defaultReverseRegistrarV1 = get<
      (typeof artifacts.DefaultReverseRegistrar)["abi"]
    >("DefaultReverseRegistrar");

    const reverseRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ReverseRegistry");

    const l2ChainId = args.l2Deploy.network.chain.id;
    const l2Registrar = args.l2Deploy.deployments.L2ReverseRegistrar.address;
    const l2CoinType = coinTypeFromChain(l2ChainId);
    const l2CoinTypeHex = l2CoinType.toString(16);

    console.log("Deploying NamechainReverseResolver with:");
    console.log("  - L2 coin type:", l2CoinType, `(0x${l2CoinTypeHex})`);
    console.log("  - L2 registrar:", l2Registrar);
    console.log("  - Verifier:", args.verifierAddress);

    const namechainReverseResolver = await deploy("NamechainReverseResolver", {
      account: deployer,
      artifact: artifacts.ChainReverseResolver,
      args: [
        owner,
        l2CoinType,
        defaultReverseRegistrarV1.address,
        l2Registrar,
        args.verifierAddress,
        args.verifierGateways,
      ],
    });

    console.log(
      "Deployed NamechainReverseResolver at:",
      namechainReverseResolver.address,
    );

    // Register "{l2CoinTypeHex}.reverse" (e.g., "80eeeeee.reverse" for namechain)
    await write(reverseRegistry, {
      account: deployer,
      functionName: "register",
      args: [
        l2CoinTypeHex,
        owner,
        zeroAddress,
        namechainReverseResolver.address,
        0n,
        MAX_EXPIRY,
      ],
    });

    console.log(
      `Registered ${l2CoinTypeHex}.reverse with ChainReverseResolver`,
    );
  },
  {
    tags: ["NamechainReverseResolver", "l1"],
    dependencies: ["ReverseRegistry", "DefaultReverseRegistrar"],
  },
);
