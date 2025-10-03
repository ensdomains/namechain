import type { NetworkConnection } from "hardhat/types/network";
import { type Address, labelhash, zeroAddress } from "viem";
import { ROLES } from "../../../deploy/constants.js";
import { splitName } from "../../utils/utils.js";
import { deployVerifiableProxy } from "./deployVerifiableProxy.js";
export { ROLES };

export const MAX_EXPIRY = (1n << 64n) - 1n; // see: DatastoreUtils.sol

export async function deployV2Fixture(
  network: NetworkConnection,
  enableCcipRead = false,
) {
  const publicClient = await network.viem.getPublicClient({
    ccipRead: enableCcipRead ? undefined : false,
  });
  const [walletClient] = await network.viem.getWalletClients();
  const datastore = await network.viem.deployContract("RegistryDatastore");
  const hcaFactory = await network.viem.deployContract("MockHCAFactoryBasic");
  const rootRegistry = await network.viem.deployContract(
    "PermissionedRegistry",
    [
      datastore.address,
      hcaFactory.address,
      zeroAddress,
      walletClient.account.address,
      ROLES.ALL,
    ],
  );
  const ethRegistry = await network.viem.deployContract(
    "PermissionedRegistry",
    [
      datastore.address,
      hcaFactory.address,
      zeroAddress,
      walletClient.account.address,
      ROLES.ALL,
    ],
  );
  const batchGatewayProvider = await network.viem.deployContract(
    "GatewayProvider",
    [walletClient.account.address, ["x-batch-gateway:true"]],
  );
  const universalResolver = await network.viem.deployContract(
    "UniversalResolverV2",
    [rootRegistry.address, batchGatewayProvider.address],
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
  const dedicatedResolverFactory =
    await network.viem.deployContract("VerifiableFactory");
  const dedicatedResolverImpl =
    await network.viem.deployContract("DedicatedResolver");
  return {
    network,
    publicClient,
    walletClient,
    datastore,
    hcaFactory,
    rootRegistry,
    ethRegistry,
    batchGatewayProvider,
    universalResolver,
    deployDedicatedResolver,
    setupName,
  };
  async function deployDedicatedResolver({
    owner = walletClient.account.address,
    salt = BigInt(labelhash(new Date().toISOString())),
  }: {
    owner?: Address;
    salt?: bigint;
  } = {}) {
    return deployVerifiableProxy({
      walletClient: await network.viem.getWalletClient(owner),
      factoryAddress: dedicatedResolverFactory.address,
      implAddress: dedicatedResolverImpl.address,
      implAbi: dedicatedResolverImpl.abi,
      salt,
    });
  }
  // creates registries up to the parent name
  // if exact, exactRegistry is setup
  // if no resolverAddress, dedicatedResolver is deployed
  async function setupName<
    exact_ extends boolean = false,
    resolver_ extends false | Address = false,
  >({
    name,
    owner = walletClient.account.address,
    expiry = MAX_EXPIRY,
    roles = ROLES.ALL,
    resolverAddress,
    metadataAddress = zeroAddress,
    exact,
  }: {
    name: string;
    owner?: Address;
    expiry?: bigint;
    roles?: bigint;
    resolverAddress?: resolver_ | Address;
    metadataAddress?: Address;
    exact?: exact_;
  }) {
    const labels = splitName(name);
    if (!labels.length) throw new Error("expected name");
    const dedicatedResolver = resolverAddress
      ? undefined
      : await deployDedicatedResolver({ owner });
    if (!resolverAddress) {
      resolverAddress = dedicatedResolver?.address ?? zeroAddress;
    }
    const registries = [rootRegistry];
    while (true) {
      const parentRegistry = registries[0];
      const label = labels[labels.length - registries.length];
      const [tokenId] = await parentRegistry.read.getNameData([label]);
      const registryOwner = await parentRegistry.read.ownerOf([tokenId]);
      const exists = registryOwner !== zeroAddress;
      const leaf = registries.length == labels.length;
      let registryAddress = await parentRegistry.read.getSubregistry([label]);
      if (!leaf || exact) {
        if (registryAddress === zeroAddress) {
          // registry does not exist, create it
          const registry = await network.viem.deployContract(
            "PermissionedRegistry",
            [
              datastore.address,
              hcaFactory.address,
              metadataAddress,
              walletClient.account.address,
              roles,
            ],
          );
          registryAddress = registry.address;
          if (exists) {
            // label exists but registry does not exist, set it
            await parentRegistry.write.setSubregistry([
              tokenId,
              registryAddress,
            ]);
          }
          registries.unshift(registry);
        } else {
          registries.unshift(
            await network.viem.getContractAt(
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
        //            tokenId == labelToCanonicalId(labels[0])
        //  registries.length == labels.length
        //     exactRegistry? == registries[0]
        //     parentRegistry == registries[1]
        // dedicatedResolver? == !resolverAddress
        return {
          labels,
          tokenId,
          parentRegistry,
          exactRegistry: (exact
            ? registries[0]
            : undefined) as exact_ extends true
            ? (typeof registries)[number]
            : undefined,
          registries: (exact
            ? registries
            : [undefined, ...registries]) as exact_ extends true
            ? typeof registries
            : [undefined, ...typeof registries],
          dedicatedResolver: dedicatedResolver as resolver_ extends false
            ? NonNullable<typeof dedicatedResolver>
            : undefined,
        };
      }
    }
  }
}
