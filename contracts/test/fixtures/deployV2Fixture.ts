import hre from "hardhat";
import {
  type Address,
  encodeFunctionData,
  labelhash,
  parseEventLogs,
  zeroAddress,
} from "viem";
import { splitName } from "../utils/utils.js";

export const MAX_EXPIRY = (1n << 64n) - 1n; // see: DatastoreUtils.sol

// see: RegistryRolesMixin.sol
const FLAGS = {
  REGISTRAR: 1n << 0n,
  RENEW: 1n << 1n,
  SET_SUBREGISTRY: 1n << 2n,
  SET_RESOLVER: 1n << 3n,
  SET_TOKEN_OBSERVER: 1n << 4n,
  MASK: (1n << 128n) - 1n,
} as const;
export const ROLES = {
  OWNER: FLAGS,
  ADMIN: Object.fromEntries(
    Object.entries(FLAGS).map(([k, v]) => [k, v << 128n]),
  ) as typeof FLAGS,
  ALL: (1n << 256n) - 1n, // see: EnhancedAccessControl.sol
} as const;

export async function deployV2Fixture(batchGateways: string[] = []) {
  const publicClient = await hre.viem.getPublicClient({
    ccipRead: batchGateways.length ? undefined : false,
  });
  const [walletClient] = await hre.viem.getWalletClients();
  const datastore = await hre.viem.deployContract("RegistryDatastore", []);
  const rootRegistry = await hre.viem.deployContract("PermissionedRegistry", [
    datastore.address,
    zeroAddress,
    ROLES.ALL,
  ]);
  const ethRegistry = await hre.viem.deployContract("PermissionedRegistry", [
    datastore.address,
    zeroAddress,
    ROLES.ALL,
  ]);
  const universalResolver = await hre.viem.deployContract(
    "UniversalResolver",
    [rootRegistry.address, batchGateways],
    {
      client: { public: publicClient },
    },
  );
  await rootRegistry.write.register([
    "eth",
    walletClient.account.address,
    ethRegistry.address,
    zeroAddress,
    ROLES.ALL,
    MAX_EXPIRY,
  ]);
  const verifiableFactory = await hre.viem.deployContract(
    "@ensdomains/verifiable-factory/VerifiableFactory.sol:VerifiableFactory",
  );
  const ownedResolverImpl = await hre.viem.deployContract("OwnedResolver");
  const ownedResolver = await deployOwnedResolver({
    owner: walletClient.account.address,
  });
  return {
    publicClient,
    walletClient,
    datastore,
    rootRegistry,
    ethRegistry,
    universalResolver,
    verifiableFactory,
    ownedResolver,
    deployOwnedResolver,
    setupName,
  };
  async function deployOwnedResolver({
    owner,
    salt = BigInt(labelhash(new Date().toISOString())),
  }: {
    owner: Address;
    salt?: bigint;
  }) {
    const wallet = await hre.viem.getWalletClient(owner);
    const hash = await verifiableFactory.write.deployProxy([
      ownedResolverImpl.address,
      salt,
      encodeFunctionData({
        abi: ownedResolverImpl.abi,
        functionName: "initialize",
        args: [owner],
      }),
    ]);
    const receipt = await publicClient.getTransactionReceipt({
      hash,
    });
    const [log] = parseEventLogs({
      abi: verifiableFactory.abi,
      eventName: "ProxyDeployed",
      logs: receipt.logs,
    });
    return hre.viem.getContractAt("OwnedResolver", log.args.proxyAddress, {
      client: {
        wallet,
      },
    });
  }
  // creates registries up to the parent name
  async function setupName({
    name,
    owner = walletClient.account.address,
    expiry = MAX_EXPIRY,
    roles = ROLES.ALL,
    resolverAddress = ownedResolver.address,
    metadataAddress = zeroAddress,
  }: {
    name: string;
    owner?: Address;
    expiry?: bigint;
    roles?: bigint;
    resolverAddress?: Address;
    metadataAddress?: Address;
  }) {
    const labels = splitName(name);
    if (!labels.length) throw new Error("expected name");
    const registries = [rootRegistry];
    while (true) {
      const parentRegistry = registries[registries.length - 1];
      const label = labels.pop()!;
      const [tokenId] = await parentRegistry.read.getNameData([label]);
      const registryOwner = await parentRegistry.read.ownerOf([tokenId]);
      const exists = registryOwner !== zeroAddress;
      let registryAddress = await parentRegistry.read.getSubregistry([label]);
      if (labels.length) {
        // this is an inner node
        if (registryAddress === zeroAddress) {
          // registry does not exist, create it
          const registry = await hre.viem.deployContract(
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
            await hre.viem.getContractAt(
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
          labels.length ? registryAddress : zeroAddress,
          labels.length ? zeroAddress : resolverAddress,
          roles,
          expiry,
        ]);
      } else if (!labels.length) {
        const currentResolver = await parentRegistry.read.getResolver([label]);
        if (currentResolver !== resolverAddress) {
          // leaf node exists but resolver is different, set it
          await parentRegistry.write.setResolver([tokenId, resolverAddress]);
        }
      }
      if (!labels.length) {
        // registries.length == labels.length - 1
        // parentRegistry == registries.at(-1)
        // tokenId = canonical(labelhash(labels.at(-1)))
        return { registries, labels, tokenId, parentRegistry };
      }
    }
  }
}
