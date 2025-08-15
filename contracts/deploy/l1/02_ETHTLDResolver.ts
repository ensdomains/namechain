import { artifacts, execute } from "@rocketh";
import {
  type Address,
  type RpcLog,
  encodeFunctionData,
  parseEventLogs,
  zeroAddress,
} from "viem";

export default execute<{
  l2Deploy: {
    deployments: Record<string, { address: Address }>;
  };
  verifierAddress: Address;
}>(
  async (
    { deploy, execute, get, deployments, namedAccounts: { deployer }, network },
    args,
  ) => {
    if (!args) throw new Error("expected L2 deployment");

    const ethRegistrarV1 = get("ETHRegistrarV1");
    const universalResolverV1 = get("UniversalResolverV1");

    const verifiableFactory = get<(typeof artifacts.VerifiableFactory)["abi"]>(
      "DedicatedResolverFactory",
    );
    const dedicatedResolverImpl = get<
      (typeof artifacts.DedicatedResolver)["abi"]
    >("DedicatedResolverImpl");

    const hash = await execute(verifiableFactory, {
      account: deployer,
      functionName: "deployProxy",
      args: [
        dedicatedResolverImpl.address,
        1n,
        encodeFunctionData({
          abi: dedicatedResolverImpl.abi,
          functionName: "initialize",
          args: [deployer],
        }),
      ],
    });

    /// ???
    const receipt = await network.provider.request<{ logs: RpcLog[] }>({
      method: "eth_getTransactionReceipt",
      params: [hash],
    });

    const [log] = parseEventLogs({
      abi: verifiableFactory.abi,
      eventName: "ProxyDeployed",
      logs: receipt.logs,
    });

    // ???
    deployments["ETHDedicatedResolver"] = {
      ...dedicatedResolverImpl,
      address: log.args.proxyAddress,
    };

    const ethDedicatedResolver = get<
      (typeof artifacts.DedicatedResolver)["abi"]
    >("ETHDedicatedResolver");

    const ethTLDResolver = await deploy("ETHTLDResolver", {
      account: deployer,
      artifact: artifacts.ETHTLDResolver,
      args: [
        ethRegistrarV1.address,
        universalResolverV1.address,
        zeroAddress, // burnAddressV1
        ethDedicatedResolver.address,
        args.verifierAddress,
        args.l2Deploy.deployments.RegistryDatastore.address,
        args.l2Deploy.deployments.ETHRegistry.address,
        32,
      ],
    });

    await execute(ethDedicatedResolver, {
      account: deployer,
      functionName: "setAddr",
      args: [60n, ethTLDResolver.address],
    });
  },
  {
    tags: ["ETHTLDResolver", "l1"],
    dependencies: ["DedicatedResolver", "MockL1"],
  },
);
