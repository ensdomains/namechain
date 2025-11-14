import { artifacts, execute } from "@rocketh";
import { type RpcLog, encodeFunctionData, parseEventLogs } from "viem";

export default execute(
  async (
    { deploy, execute: write, get, save, namedAccounts: { deployer }, network },
    args,
  ) => {
    if (!args?.l2Deploy) throw new Error("expected L2 deployment");

    const nameWrapper =
      get<(typeof artifacts.NameWrapper)["abi"]>("NameWrapper");

    const batchGatewayProvider = get<(typeof artifacts.GatewayProvider)["abi"]>(
      "BatchGatewayProvider",
    );

    const ethRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ETHRegistry");

    const bridgeController =
      get<(typeof artifacts.L1BridgeController)["abi"]>("BridgeController");

    const verifiableFactory =
      get<(typeof artifacts.VerifiableFactory)["abi"]>("VerifiableFactory");

    const dedicatedResolverImpl = get<
      (typeof artifacts.DedicatedResolver)["abi"]
    >("DedicatedResolverImpl");

    const hash = await write(verifiableFactory, {
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

    const ethSelfResolver = await save("ETHSelfResolver", {
      ...dedicatedResolverImpl,
      address: log.args.proxyAddress,
    });

    const ethTLDResolver = await deploy("ETHTLDResolver", {
      account: deployer,
      artifact: artifacts.ETHTLDResolver,
      args: [
        nameWrapper.address,
        batchGatewayProvider.address,
        ethRegistry.address,
        bridgeController.address,
        ethSelfResolver.address,
        args.verifierAddress,
        args.l2Deploy.deployments.RegistryDatastore.address,
        args.l2Deploy.deployments.ETHRegistry.address,
      ],
    });

    await write(ethSelfResolver, {
      account: deployer,
      functionName: "setAddr",
      args: [60n, ethTLDResolver.address],
    });
  },
  {
    tags: ["ETHTLDResolver", "l1"],
    dependencies: [
      "NameWrapper",
      "BatchGatewayProvider",
      "ETHRegistry",
      "BridgeController",
      "VerifiableFactory",
      "DedicatedResolver",
    ],
  },
);
