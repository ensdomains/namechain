import { evmChainIdToCoinType } from "@ensdomains/address-encoder/utils";
import { artifacts, execute } from "@rocketh";
import { namehash, zeroAddress } from "viem";
import type { RockethL1Arguments } from "../../script/types.js";
import { LOCAL_BATCH_GATEWAY_URL, MAX_EXPIRY } from "../constants.js";

export default execute(
  async (
    {
      deploy,
      execute: write,
      get,
      namedAccounts: { deployer, owner },
      network,
    },
    args: RockethL1Arguments,
  ) => {
    const l2Deploy = args?.l2Deploy;
    if (!l2Deploy) {
      console.log("Skipping NamechainReverseResolver: no L2 deployment");
      return;
    }

    const verifierAddress = args?.verifierAddress;
    if (!verifierAddress) {
      console.log("Skipping NamechainReverseResolver: no verifier address");
      return;
    }

    const defaultReverseRegistrarV1 = get<
      (typeof artifacts.DefaultReverseRegistrar)["abi"]
    >("DefaultReverseRegistrar");

    const reverseRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ReverseRegistry");

    const l2ChainId = l2Deploy.network.chain.id;
    const l2CoinType = evmChainIdToCoinType(l2ChainId);
    const l2CoinTypeHex = l2CoinType.toString(16);
    const l2ReverseRegistrar = l2Deploy.get("L2ReverseRegistrar");

    const gatewayURLs = process.env.BATCH_GATEWAY_URLS
      ? JSON.parse(process.env.BATCH_GATEWAY_URLS)
      : [LOCAL_BATCH_GATEWAY_URL];

    console.log("Deploying NamechainReverseResolver with:");
    console.log("  - L2 coin type:", l2CoinType, `(0x${l2CoinTypeHex})`);
    console.log("  - L2 registrar:", l2ReverseRegistrar.address);
    console.log("  - Verifier:", verifierAddress);
    console.log("  - Gateway URLs:", gatewayURLs);

    const namechainReverseResolver = await deploy("NamechainReverseResolver", {
      account: deployer,
      artifact: artifacts.ChainReverseResolver,
      args: [
        owner,
        l2CoinType,
        defaultReverseRegistrarV1.address,
        l2ReverseRegistrar.address,
        verifierAddress,
        gatewayURLs,
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
