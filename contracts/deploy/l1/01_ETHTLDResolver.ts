import { artifacts, execute } from "@rocketh";
import {
  type RpcLog,
  encodeFunctionData,
  parseEventLogs,
  zeroAddress,
} from "viem";
import { ROLES } from "../constants.ts";

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

    const batchGatewayProvider = getV1<
      (typeof artifacts.GatewayProvider)["abi"]
    >("BatchGatewayProvider");

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
        ensRegistryV1.address,
        batchGatewayProvider.address,
        zeroAddress, // burnAddressV1
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
      "VerifiableFactory",
      "DedicatedResolver",
      "BaseRegistrarImplementation", // "ENSRegistry"
      "BatchGatewayProvider",
    ],
  },
);
