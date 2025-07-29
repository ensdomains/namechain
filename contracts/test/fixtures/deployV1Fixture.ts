import type { NetworkConnection } from "hardhat/types/network";
import { type Address, labelhash, namehash, zeroAddress } from "viem";
import { splitName } from "../utils/utils.js";

export async function deployV1Fixture<C extends NetworkConnection>(
  nc: C,
  enableCcipRead = false,
) {
  const publicClient = await nc.viem.getPublicClient({
    ccipRead: enableCcipRead ? undefined : false,
  });
  const [walletClient] = await nc.viem.getWalletClients();
  const ensRegistry = await nc.viem.deployContract("ENSRegistry");
  const ethRegistrar = await nc.viem.deployContract(
    "BaseRegistrarImplementation",
    [ensRegistry.address, namehash("eth")],
  );
  const reverseRegistrar = await nc.viem.deployContract("ReverseRegistrar", [
    ensRegistry.address,
  ]);
  await ensRegistry.write.setSubnodeOwner([
    namehash(""),
    labelhash("reverse"),
    walletClient.account.address,
  ]);
  await ensRegistry.write.setSubnodeOwner([
    namehash("reverse"),
    labelhash("addr"),
    reverseRegistrar.address,
  ]);
  const publicResolver = await nc.viem.deployContract("PublicResolver", [
    ensRegistry.address,
    zeroAddress, // TODO: this setup is incomplete
    zeroAddress, // no wrapper, no controller
    reverseRegistrar.address,
  ]);
  await reverseRegistrar.write.setDefaultResolver([publicResolver.address]);
  const batchGatewayProvider = await nc.viem.deployContract("GatewayProvider", [
    ["x-batch-gateway:true"],
  ]);
  const universalResolver = await nc.viem.deployContract(
    "UniversalResolver",
    [
      walletClient.account.address,
      ensRegistry.address,
      batchGatewayProvider.address,
    ],
    { client: { public: publicClient } },
  );
  await ethRegistrar.write.addController([walletClient.account.address]);
  await ensRegistry.write.setSubnodeRecord([
    namehash(""),
    labelhash("eth"),
    walletClient.account.address,
    zeroAddress,
    0n,
  ]);
  await publicResolver.write.setAddr([namehash("eth"), ethRegistrar.address]);
  await ensRegistry.write.setSubnodeOwner([
    namehash(""),
    labelhash("eth"),
    ethRegistrar.address,
  ]);
  return {
    publicClient,
    walletClient,
    ensRegistry,
    reverseRegistrar,
    ethRegistrar,
    publicResolver,
    batchGatewayProvider,
    universalResolver,
    setupName,
  };
  // clobbers registry ownership up to name
  // except for "eth" (since registrar is known)
  async function setupName({
    name,
    resolverAddress = publicResolver.address,
  }: {
    name: string;
    resolverAddress?: Address;
  }) {
    const labels = splitName(name);
    let i = labels.length;
    if (name.endsWith(".eth")) {
      await ethRegistrar.write.register([
        BigInt(labelhash(labels[(i -= 2)])),
        walletClient.account.address,
        (1n << 64n) - 1n,
      ]);
    }
    while (i > 0) {
      const parent = labels.slice(i).join(".");
      const child = labels[--i];
      await ensRegistry.write.setSubnodeOwner([
        namehash(parent),
        labelhash(child),
        walletClient.account.address,
      ]);
    }
    // set resolver on leaf
    await ensRegistry.write.setResolver([namehash(name), resolverAddress]);
    return { labels };
  }
}
