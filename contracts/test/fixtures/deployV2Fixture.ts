import hre from "hardhat";
import {
  type Address,
  encodeFunctionData,
  labelhash,
  parseEventLogs,
  zeroAddress,
} from "viem";

export const ALL_ROLES = (1n << 256n) - 1n;
export const MAX_EXPIRY = (1n << 64n) - 1n;

export async function deployV2Fixture(batchGateways: string[] = []) {
  const publicClient = await hre.viem.getPublicClient({
    ccipRead: batchGateways ? undefined : false,
  });
  const accounts = (await hre.viem.getWalletClients()).map((x) => x.account);
  const datastore = await hre.viem.deployContract("RegistryDatastore", []);
  const rootRegistry = await hre.viem.deployContract("PermissionedRegistry", [
    datastore.address,
    zeroAddress,
    ALL_ROLES,
  ]);
  const ethRegistry = await hre.viem.deployContract("PermissionedRegistry", [
    datastore.address,
    zeroAddress,
    ALL_ROLES,
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
    accounts[0].address,
    ethRegistry.address,
    zeroAddress,
    ALL_ROLES,
    MAX_EXPIRY,
  ]);
  const verifiableFactory = await hre.viem.deployContract(
    "@ensdomains/verifiable-factory/VerifiableFactory.sol:VerifiableFactory",
  );
  const ownedResolverImpl = await hre.viem.deployContract("OwnedResolver");
  const ownedResolver = await deployOwnedResolver({
    owner: accounts[0].address,
  });
  return {
    publicClient,
    accounts,
    datastore,
    rootRegistry,
    ethRegistry,
    universalResolver,
    verifiableFactory,
    ownedResolver,
    deployOwnedResolver,
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
}

export type EnsFixture = Awaited<ReturnType<typeof deployV2Fixture>>;

export const deployUserRegistry = async ({
  datastoreAddress,
  metadataAddress = zeroAddress,
  ownerIndex = 0,
}: {
  datastoreAddress: Address;
  metadataAddress?: Address;
  ownerIndex?: number;
}) => {
  const wallet = (await hre.viem.getWalletClients())[ownerIndex];
  return await hre.viem.deployContract(
    "PermissionedRegistry",
    [datastoreAddress, metadataAddress, ALL_ROLES],
    {
      client: { wallet },
    },
  );
};

export const registerName = async ({
  ethRegistry,
  label,
  expiry = BigInt(Math.floor(Date.now() / 1000) + 1000000),
  owner: owner_,
  subregistry = zeroAddress,
  resolver = zeroAddress,
  subregistryLocked = false,
  resolverLocked = false,
}: Pick<EnsFixture, "ethRegistry"> & {
  label: string;
  expiry?: bigint;
  owner?: Address;
  subregistry?: Address;
  resolver?: Address;
  subregistryLocked?: boolean;
  resolverLocked?: boolean;
}) => {
  const ROLE_SET_SUBREGISTRY = 1n << 2n;
  const ROLE_SET_RESOLVER = 1n << 3n;
  const owner =
    owner_ ?? (await hre.viem.getWalletClients())[0].account.address;
  const roles =
    (subregistryLocked ? 0n : ROLE_SET_SUBREGISTRY) |
    (resolverLocked ? 0n : ROLE_SET_RESOLVER);
  return ethRegistry.write.register([
    label,
    owner,
    subregistry,
    resolver,
    roles,
    expiry,
  ]);
};
