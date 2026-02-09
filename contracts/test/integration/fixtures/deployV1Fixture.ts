import type { NetworkConnection } from "hardhat/types/network";
import {
  type Account,
  type Address,
  getAddress,
  labelhash,
  namehash,
  zeroAddress,
} from "viem";
import { splitName } from "../../utils/utils.js";
import { LOCAL_BATCH_GATEWAY_URL } from "../../../script/deploy-constants.js";

export async function deployV1Fixture(
  network: NetworkConnection,
  enableCcipRead = false,
) {
  const publicClient = await network.viem.getPublicClient({
    ccipRead: enableCcipRead ? undefined : false,
  });
  const [walletClient] = await network.viem.getWalletClients();
  const ensRegistry = await network.viem.deployContract("ENSRegistry");
  const ethRegistrar = await network.viem.deployContract(
    "BaseRegistrarImplementation",
    [ensRegistry.address, namehash("eth")],
  );
  const reverseRegistrar = await network.viem.deployContract(
    "ReverseRegistrar",
    [ensRegistry.address],
  );
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
  const publicResolver = await network.viem.deployContract("PublicResolver", [
    ensRegistry.address,
    zeroAddress, // TODO: this setup is incomplete
    zeroAddress, // no wrapper, no controller
    reverseRegistrar.address,
  ]);
  await reverseRegistrar.write.setDefaultResolver([publicResolver.address]);
  const batchGatewayProvider = await network.viem.deployContract(
    "GatewayProvider",
    [walletClient.account.address, [LOCAL_BATCH_GATEWAY_URL]],
  );
  const universalResolver = await network.viem.deployContract(
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
  const nameWrapper = await network.viem.deployContract("NameWrapper", [
    ensRegistry.address,
    ethRegistrar.address,
    zeroAddress, // IMetadataService
  ]);
  return {
    network,
    publicClient,
    walletClient,
    ensRegistry,
    reverseRegistrar,
    ethRegistrar,
    publicResolver,
    batchGatewayProvider,
    universalResolver,
    nameWrapper,
    setupName,
  };
  // clobbers registry ownership up to name
  // except for "eth" (since registrar is known)
  async function setupName({
    name,
    resolverAddress = publicResolver.address,
    account = walletClient.account,
  }: {
    name: string;
    resolverAddress?: Address;
    account?: Account;
  }) {
    resolverAddress = getAddress(resolverAddress); // fix checksum
    const labels = splitName(name);
    let i = labels.length;
    if (name.endsWith(".eth")) {
      await ethRegistrar.write.register([
        BigInt(labelhash(labels[(i -= 2)])),
        account.address,
        (1n << 64n) - 1n,
      ]);
    }
    while (i > 0) {
      const parent = labels.slice(i).join(".");
      const child = labels[--i];
      await ensRegistry.write.setSubnodeOwner(
        [namehash(parent), labelhash(child), account.address],
        { account },
      );
    }
    // set resolver on leaf
    const node = namehash(name);
    await ensRegistry.write.setResolver([node, resolverAddress], { account });
    return { name, labels, resolverAddress, node };
  }
}
