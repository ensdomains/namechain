import type { NetworkConnection } from "hardhat/types/network";
import { labelhash, namehash } from "viem";
import { splitName } from "../utils/utils.js";
import { baseRegistrarImplementationArtifact } from "./ens-contracts/BaseRegistrarImplementation.js";
import { ensRegistryArtifact } from "./ens-contracts/ENSRegistry.js";
import { ownedResolverArtifact } from "./ens-contracts/OwnedResolver.js";
import { universalResolverArtifact } from "./ens-contracts/UniversalResolver.js";

export async function deployV1Fixture<C extends NetworkConnection>(
  networkConnection: C,
  enableCcipRead = false,
) {
  const publicClient = await networkConnection.viem.getPublicClient({
    ccipRead: enableCcipRead ? undefined : false,
  });
  const [walletClient] = await networkConnection.viem.getWalletClients();
  const ensRegistry =
    await networkConnection.viem.deployContract(ensRegistryArtifact);
  const ethRegistrar = await networkConnection.viem.deployContract(
    baseRegistrarImplementationArtifact,
    [ensRegistry.address, namehash("eth")],
  );
  const ownedResolver = await networkConnection.viem.deployContract(
    ownedResolverArtifact,
  );
  const universalResolver = await networkConnection.viem.deployContract(
    universalResolverArtifact,
    [ensRegistry.address, ["x-batch-gateway:true"]],
    { client: { public: publicClient } },
  );
  await ethRegistrar.write.addController([walletClient.account.address]);
  await ensRegistry.write.setSubnodeRecord([
    namehash(""),
    labelhash("eth"),
    ethRegistrar.address,
    ownedResolver.address,
    0n,
  ]);
  await ownedResolver.write.setAddr([namehash("eth"), ethRegistrar.address]);
  return {
    publicClient,
    walletClient,
    ensRegistry,
    ethRegistrar,
    ownedResolver,
    universalResolver,
    setupName,
  };
  // clobbers registry ownership up to name
  // except for "eth" (since registrar is known)
  async function setupName(name: string) {
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
    await ensRegistry.write.setResolver([
      namehash(name),
      ownedResolver.address,
    ]);
    return { labels };
  }
}
