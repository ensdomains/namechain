import { artifacts, execute } from "@rocketh";
import { labelhash, namehash, zeroAddress } from "viem";

// TODO: replace with full ens-contracts deploy
export default execute(
  async ({ deploy, execute: write, get, namedAccounts: { deployer } }) => {
    const batchGatewayProvider = get<(typeof artifacts.GatewayProvider)["abi"]>(
      "BatchGatewayProvider",
    );

    const ensRegistry = await deploy("ENSRegistryV1", {
      account: deployer,
      artifact: artifacts.ENSRegistry
    });

    const ethRegistrar = await deploy("ETHRegistrarV1", {
      account: deployer,
      artifact: artifacts.BaseRegistrarImplementation,
      args: [ensRegistry.address, namehash("eth")],
    });

    const reverseRegistrar = await deploy("ReverseRegistrarV1", {
      account: deployer,
      artifact: artifacts.ReverseRegistrar,
      args: [ensRegistry.address],
    });

	await write(ensRegistry, {
      account: deployer,
      functionName: "setSubnodeOwner",
      args: [namehash(""), labelhash("reverse"), deployer],
    });

    await write(ensRegistry, {
      account: deployer,
      functionName: "setSubnodeOwner",
      args: [namehash("reverse"), labelhash("addr"), reverseRegistrar.address],
    });

    const publicResolver = await deploy("PublicResolverV1", {
      account: deployer,
      artifact: artifacts.PublicResolver,
      args: [
        ensRegistry.address,
        zeroAddress, // TODO: add wrapper
        zeroAddress,
        reverseRegistrar.address,
      ],
    });

    await write(reverseRegistrar, {
      account: deployer,
      functionName: "setDefaultResolver",
      args: [publicResolver.address],
    });

    await deploy("UniversalResolverV1", {
      account: deployer,
      artifact: artifacts.UniversalResolver,
      args: [
        deployer,
        ensRegistry.address,
        batchGatewayProvider.address,
      ],
    });

    await write(ethRegistrar, {
      account: deployer,
      functionName: "addController",
      args: [deployer],
    });

    await write(ensRegistry, {
      account: deployer,
      functionName: "setSubnodeRecord",
      args: [namehash(""), labelhash("eth"), deployer, zeroAddress, 0n],
    });

    await write(publicResolver, {
      account: deployer,
      functionName: "setAddr",
      args: [namehash("eth"), ethRegistrar.address],
    });

    await write(ensRegistry, {
      account: deployer,
      functionName: "setSubnodeOwner",
      args: [namehash(""), labelhash("eth"), ethRegistrar.address],
    });
  },
  {
    tags: ["MockENSv1", "mocks", "l1"],
    dependencies: ["BatchGatewayProvider"],
  },
);
