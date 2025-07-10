import type { DefaultChainType, NetworkConnection } from "hardhat/types/network";
import {
  type Address,
  encodeFunctionData,
  labelhash,
  parseEventLogs,
  zeroAddress,
} from "viem";
import { splitName } from "../utils/utils.js";
import { ROLES } from "../../deploy/constants.js";
export { ROLES };

export const MAX_EXPIRY = (1n << 64n) - 1n; // see: DatastoreUtils.sol


export async function deployV2Fixture(
  networkConnection: NetworkConnection<DefaultChainType>,
  enableCcipRead = false,
) {
const publicClient = await networkConnection.viem.getPublicClient({
    ccipRead: enableCcipRead ? undefined : false,
  });
  const [walletClient] = await networkConnection.viem.getWalletClients();
  const datastore =
    await networkConnection.viem.deployContract("RegistryDatastore");
  const rootRegistry = await networkConnection.viem.deployContract(
    "PermissionedRegistry",
    [datastore.address, zeroAddress, ROLES.ALL],
  );
  const ethRegistry = await networkConnection.viem.deployContract(
    "PermissionedRegistry",
    [datastore.address, zeroAddress, ROLES.ALL],
  );
  const universalResolver = await networkConnection.viem.deployContract(
    "UniversalResolver2",
    [rootRegistry.address, ["x-batch-gateway:true"]],
    { client: { public: publicClient } },
  );
  await rootRegistry.write.register([
    "eth",
    walletClient.account.address,
    ethRegistry.address,
    zeroAddress,
    ROLES.ALL,
    MAX_EXPIRY,
  ]);
  const verifiableFactory =
    await networkConnection.viem.deployContract("VerifiableFactory");
  const dedicatedResolverImpl =
    await networkConnection.viem.deployContract("DedicatedResolver");
  const dedicatedResolver = await deployDedicatedResolver({
    owner: walletClient.account.address,
  });
  return {
    networkConnection,
    publicClient,
    walletClient,
    datastore,
    rootRegistry,
    ethRegistry,
    universalResolver,
    verifiableFactory,
    dedicatedResolver, // warning: this is owned by the default wallet
    deployDedicatedResolver,
    setupName,
  };
  async function deployDedicatedResolver({
    owner,
    salt = BigInt(labelhash(new Date().toISOString())),
  }: {
    owner: Address;
    salt?: bigint;
  }) {
    const wallet = await networkConnection.viem.getWalletClient(owner);
    const hash = await verifiableFactory.write.deployProxy([
      dedicatedResolverImpl.address,
      salt,
      encodeFunctionData({
        abi: dedicatedResolverImpl.abi,
        functionName: "initialize",
        args: [owner],
      }),
    ]);
    const receipt = await publicClient.getTransactionReceipt({ hash });
    const [log] = parseEventLogs({
      abi: verifiableFactory.abi,
      eventName: "ProxyDeployed",
      logs: receipt.logs,
    });
    return networkConnection.viem.getContractAt(
      "DedicatedResolver",
      log.args.proxyAddress,
      { client: { wallet } },
    );
  }
  // creates registries up to the parent name
  async function setupName({
    name,
    owner = walletClient.account.address,
    expiry = MAX_EXPIRY,
    roles = ROLES.ALL,
    resolverAddress = dedicatedResolver.address,
    metadataAddress = zeroAddress,
    exact = false,
  }: {
    name: string;
    owner?: Address;
    expiry?: bigint;
    roles?: bigint;
    resolverAddress?: Address;
    metadataAddress?: Address;
    exact?: boolean;
  }) {
    const labels = splitName(name);
    if (!labels.length) throw new Error("expected name");
    const registries = [rootRegistry];
    while (true) {
      const parentRegistry = registries[registries.length - 1];
      const label = labels[labels.length - registries.length];
      const [tokenId] = await parentRegistry.read.getNameData([label]);
      const registryOwner = await parentRegistry.read.ownerOf([tokenId]);
      const exists = registryOwner !== zeroAddress;
      const leaf = registries.length == labels.length;
      let registryAddress = await parentRegistry.read.getSubregistry([label]);
      if (!leaf || exact) {
        if (registryAddress === zeroAddress) {
          // registry does not exist, create it
          const registry = await networkConnection.viem.deployContract(
            "PermissionedRegistry",
            [datastore.address, metadataAddress, roles],
          );
          registryAddress = registry.address;
          if (exists) {
            // label exists but registry does not exist, set it
            await parentRegistry.write.setSubregistry([
              tokenId,
              registryAddress,
            ]);
          }
          registries.push(registry);
        } else {
          registries.push(
            await networkConnection.viem.getContractAt(
              "PermissionedRegistry",
              registryAddress,
            ),
          );
        }
      }
      if (!exists) {
        // child does not exist, register it
        await parentRegistry.write.register([
          label,
          owner,
          registryAddress,
          leaf ? resolverAddress : zeroAddress,
          roles,
          expiry,
        ]);
      } else if (leaf) {
        const currentResolver = await parentRegistry.read.getResolver([label]);
        if (currentResolver !== resolverAddress) {
          // leaf node exists but resolver is different, set it
          await parentRegistry.write.setResolver([tokenId, resolverAddress]);
        }
      }
      if (leaf) {
        // invariants:
        //  registries.length == labels.length - (exact ? 0 : 1)
        //     parentRegistry == registries.at(exact ? -2 : -1)
        //            tokenId == canonical(labelhash(labels.at(-1)))
        return { registries, labels, tokenId, parentRegistry };
      }
    }
  }
}
