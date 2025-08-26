import { artifacts, execute } from "@rocketh";
import { zeroAddress } from "viem";
import { MAX_EXPIRY } from "../constants.js";

export default execute(
  async ({ deploy, execute: write, get, namedAccounts: { deployer } }) => {
    const ensRegistryV1 =
      get<(typeof artifacts.ENSRegistry)["abi"]>("ENSRegistry");

    const dnsTLDResolverV1 = get<(typeof artifacts.OffchainDNSResolver)["abi"]>(
      "OffchainDNSResolver",
    );

    const rootRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("RootRegistry");

    const dnssecOracle = get<(typeof artifacts.DNSSEC)["abi"]>("DNSSECImpl");

    const batchGatewayProvider = get<(typeof artifacts.GatewayProvider)["abi"]>(
      "BatchGatewayProvider",
    );

    const dnssecGatewayProvider = get<
      (typeof artifacts.GatewayProvider)["abi"]
    >("DNSSECGatewayProvider");

    const dnsTLDResolver = await deploy("DNSTLDResolver", {
      account: deployer,
      artifact: artifacts.DNSTLDResolver,
      args: [
        ensRegistryV1.address,
        dnsTLDResolverV1.address,
        rootRegistry.address,
        dnssecOracle.address,
        dnssecGatewayProvider.address,
        batchGatewayProvider.address,
      ],
    });

    // TODO: fix me
    for (const tld of ["com", "org", "net", "xyz"]) {
      await write(rootRegistry, {
        account: deployer,
        functionName: "register",
        args: [
          tld,
          deployer, // ?
          zeroAddress,
          dnsTLDResolver.address,
          0n, // ?
          MAX_EXPIRY,
        ],
      });
    }
  },
  {
    tags: ["DNSTLDResolver", "l1"],
    dependencies: [
      "RootRegistry",
      "OffchainDNSResolver", // "ENSRegistry" + "DNSSECImpl"
      "BatchGatewayProvider",
      "DNSSECGatewayProvider",
    ],
  },
);
