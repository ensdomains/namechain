import hre from "hardhat";
import { deployArtifact } from "./deployArtifact.js";
import { ensArtifact } from "./externalArtifacts.js";
import { labelhash, namehash } from "viem";
import { splitName } from "../utils/utils.js";

export async function deployV1Fixture(batchGateways: string[] = []) {
  const publicClient = await hre.viem.getPublicClient({
    ccipRead: batchGateways.length ? undefined : false,
  });
  const [walletClient] = await hre.viem.getWalletClients();
  const ensRegistry = await hre.viem.getContractAt(
    "@ens/contracts/registry/ENSRegistry.sol:ENSRegistry",
    await deployArtifact({
      file: ensArtifact("ENSRegistry"),
    }),
  );
  const ethRegistrar = await hre.viem.getContractAt(
    "@ens/contracts/ethregistrar/IBaseRegistrar.sol:IBaseRegistrar",
    await deployArtifact({
      file: ensArtifact("BaseRegistrarImplementation"),
      args: [ensRegistry.address, namehash("eth")],
    }),
  );
  const ownedResolver = await hre.viem.getContractAt(
    "OwnedResolver", // :)
    await deployArtifact({
      file: ensArtifact("OwnedResolver"),
    }),
  );
  const universalResolver = await hre.viem.getContractAt(
    "@ens/contracts/universalResolver/IUniversalResolver.sol:IUniversalResolver",
    await deployArtifact({
      file: ensArtifact("UniversalResolver"),
      args: [ensRegistry.address, batchGateways],
    }),
    {
      client: { public: publicClient },
    },
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
    setupResolver,
  };
  async function setupResolver(name: string) {
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
    await ensRegistry.write.setResolver([
      namehash(name),
      ownedResolver.address,
    ]);
  }
}
