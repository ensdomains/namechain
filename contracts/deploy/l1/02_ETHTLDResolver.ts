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

    const ensRegistryV1 = get("ENSRegistryV1");
    const batchGatewayProvider = get("BatchGatewayProvider");

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
    const selfName = "ETHSelfResolver";
    deployments[selfName] = {
      ...dedicatedResolverImpl,
      address: log.args.proxyAddress,
    };

    const ethSelfResolver =
      get<(typeof artifacts.DedicatedResolver)["abi"]>(selfName);

    const ethTLDResolver = await deploy("ETHTLDResolver", {
      account: deployer,
      artifact: artifacts.ETHTLDResolver,
      args: [
        ensRegistryV1.address,
        batchGatewayProvider.address,
        zeroAddress, // burnAddressV1
        ethSelfResolver.address,
        args.verifierAddress,
        args.l2Deploy.deployments.RegistryDatastore.address,
        args.l2Deploy.deployments.ETHRegistry.address,
        32,
      ],
    });

    await execute(ethSelfResolver, {
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
