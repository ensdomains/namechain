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

interface Flags {
  [key: string]: bigint | Flags;
}
const FLAGS = {
  // see: RegistryRolesMixin.sol
  EAC: {
    REGISTRAR: 1n << 0n,
    RENEW: 1n << 1n,
    SET_SUBREGISTRY: 1n << 2n,
    SET_RESOLVER: 1n << 3n,
    SET_TOKEN_OBSERVER: 1n << 4n,
  },
  // see: L2/ETHRegistry.sol
  ETH: {
    SET_PRICE_ORACLE: 1n << 0n,
    SET_COMMITMENT_AGES: 1n << 1n,
  },
  // see: L2/UserRegistry.sol
  USER: {
    UPGRADE: 1n << 5n,
  },
  MASK: (1n << 128n) - 1n,
} as const satisfies Flags;
function mapFlags(flags: Flags, fn: (x: bigint) => bigint): Flags {
  return Object.fromEntries(
    Object.entries(flags).map(([k, x]) => [
      k,
      typeof x === "bigint" ? fn(x) : mapFlags(x, fn),
    ]),
  );
}
export const ROLES = {
  OWNER: FLAGS,
  ADMIN: mapFlags(FLAGS, (x) => x << 128n),
  ALL: (1n << 256n) - 1n, // see: EnhancedAccessControl.sol
} as const;

export async function deployV2Fixture(enableCcipRead = false) {
  const publicClient = await hre.viem.getPublicClient({
    ccipRead: enableCcipRead ? undefined : false,
  });
  const [walletClient] = await hre.viem.getWalletClients();
  const datastore = await hre.viem.deployContract("RegistryDatastore");
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
    [rootRegistry.address, ["x-batch-gateway:true"]],
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
