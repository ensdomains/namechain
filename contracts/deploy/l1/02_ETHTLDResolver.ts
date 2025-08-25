import { artifacts, execute } from "@rocketh";
import {
  type RpcLog,
  encodeFunctionData,
  parseEventLogs,
  zeroAddress,
} from "viem";

export default execute(
  async (
    { deploy, execute: write, get, save, namedAccounts: { deployer }, network },
    args,
  ) => {
    if (!args?.l2Deploy) throw new Error("expected L2 deployment");

    const ensRegistryV1 =
      get<(typeof artifacts.ENSRegistry)["abi"]>("ENSRegistry");

    const batchGatewayProvider = get<(typeof artifacts.GatewayProvider)["abi"]>(
      "BatchGatewayProvider",
    );

    const verifiableFactory = get<(typeof artifacts.VerifiableFactory)["abi"]>(
      "DedicatedResolverFactory",
    );

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

    await write(ethSelfResolver, {
      account: deployer,
      functionName: "setAddr",
      args: [60n, ethTLDResolver.address],
    });
  },
  {
    tags: ["ETHTLDResolver", "l1"],
    dependencies: ["DedicatedResolver", "ENSRegistry", "BatchGatewayProvider"],
  },
);
