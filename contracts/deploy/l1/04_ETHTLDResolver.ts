import { artifacts, execute } from "@rocketh";
import { type RpcLog, encodeFunctionData, parseEventLogs } from "viem";
import { ROLES } from "../constants.js";

export default execute(
  async (
    {
      deploy,
      execute: write,
      get,
      getV1,
      save,
      namedAccounts: { deployer },
      network,
    },
    args,
  ) => {
    if (!args?.l2Deploy) throw new Error("expected L2 deployment");

    const ensRegistryV1 =
      getV1<(typeof artifacts.ENSRegistry)["abi"]>("ENSRegistry");
    const nameWrapper =
      getV1<(typeof artifacts.NameWrapper)["abi"]>("NameWrapper");

    const batchGatewayProvider = getV1<
      (typeof artifacts.GatewayProvider)["abi"]
    >("BatchGatewayProvider");

    const ethRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ETHRegistry");

    const bridgeController =
      get<(typeof artifacts.L1BridgeController)["abi"]>("BridgeController");

    const verifiableFactory =
      get<(typeof artifacts.VerifiableFactory)["abi"]>("VerifiableFactory");

    const dedicatedResolver =
      get<(typeof artifacts.DedicatedResolver)["abi"]>("DedicatedResolver");

    if (dedicatedResolver.transaction) return;

    const hash = await write(verifiableFactory, {
      account: deployer,
      functionName: "deployProxy",
      args: [
        dedicatedResolver.address,
        3n,
        encodeFunctionData({
          abi: dedicatedResolver.abi,
          functionName: "initialize",
          args: [deployer, ROLES.ALL],
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
      ...dedicatedResolver,
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
