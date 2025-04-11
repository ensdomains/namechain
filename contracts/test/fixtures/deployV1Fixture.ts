import hre from "hardhat";
import { deployArtifact } from "./deployArtifact.js";
import { ensArtifact } from "./externalArtifacts.js";
import { labelhash, namehash } from "viem";
import { splitName } from "../utils/utils.js";

export async function deployV1Fixture(batchGateways: string[] = []) {
  const publicClient = await hre.viem.getPublicClient({
    ccipRead: batchGateways ? undefined : false,
  });
  const [owner] = await hre.viem.getWalletClients();
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
      args: [ensRegistry.address, labelhash("eth")],
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
  await setupResolver("eth");
  await ownedResolver.write.setAddr([namehash('eth'), ethRegistrar.address]);
  return {
    publicClient,
    ensRegistry,
    ethRegistrar,
    ownedResolver,
    universalResolver,
	setupResolver,
  };
  async function setupResolver(name: string) {
    const labels = splitName(name);
    for (let i = labels.length; i > 0; i--) {
      await ensRegistry.write.setSubnodeOwner([
        namehash(labels.slice(i).join(".")),
        labelhash(labels[i - 1]),
        owner.account.address,
      ]);
    }
    await ensRegistry.write.setResolver([
      namehash(name),
      ownedResolver.address,
    ]);
  }
}
