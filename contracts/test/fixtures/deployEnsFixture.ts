import hre from "hardhat";
import { type Address, bytesToHex, keccak256, stringToHex, zeroAddress } from "viem";
import { packetToBytes } from "../utils/utils.js";

export async function deployEnsFixture() {
  const publicClient = await hre.viem.getPublicClient();
  const accounts = await hre.viem
    .getWalletClients()
    .then((clients) => clients.map((c) => c.account));

  const datastore = await hre.viem.deployContract("RegistryDatastore", []);
  const rootRegistry = await hre.viem.deployContract("PermissionedRegistry", [
    datastore.address,
    zeroAddress,
  ]);
  const ethRegistry = await hre.viem.deployContract("PermissionedRegistry", [
    datastore.address,
    zeroAddress,
  ]);
  const universalResolver = await hre.viem.deployContract("UniversalResolver", [
    rootRegistry.address,
  ]);

  const ALL_ROLES = await rootRegistry.read.ALL_ROLES()
  const MAX_EXPIRY = await rootRegistry.read.MAX_EXPIRY()
  
  await rootRegistry.write.register([
    "eth",
    accounts[0].address,
    ethRegistry.address,
    zeroAddress,
    ALL_ROLES,
    MAX_EXPIRY
  ])

  return {
    publicClient,
    accounts,
    datastore,
    rootRegistry,
    ethRegistry,
    universalResolver,
  };
}

export type EnsFixture = Awaited<ReturnType<typeof deployEnsFixture>>;

export const deployUserRegistry = async ({
  name,
  parentRegistryAddress,
  datastoreAddress,
  metadataAddress,
  ownerIndex = 0,
}: {
  name: string;
  parentRegistryAddress: Address;
  datastoreAddress: Address;
  metadataAddress?: Address;
  ownerIndex?: number;
}) => {
  const wallet = (await hre.viem.getWalletClients())[ownerIndex];
  return await hre.viem.deployContract(
    "PermissionedRegistry",
    [datastoreAddress, metadataAddress ?? zeroAddress],
    {
      client: { wallet },
    }
  );
};

export const registerName = async ({
  ethRegistry,
  label,
  expiry = BigInt(Math.floor(Date.now() / 1000) + 1000000),
  owner: owner_,
  subregistry = "0x0000000000000000000000000000000000000000",
  resolver = "0x0000000000000000000000000000000000000000",
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
  const [ROLE_SET_SUBREGISTRY, ROLE_SET_RESOLVER] = await Promise.all([
    ethRegistry.read.ROLE_SET_SUBREGISTRY(),
    ethRegistry.read.ROLE_SET_RESOLVER(),
  ]);
  const owner =
    owner_ ?? (await hre.viem.getWalletClients())[0].account.address;
  const roles = (subregistryLocked ? 0n : ROLE_SET_RESOLVER) | (resolverLocked ? 0n : ROLE_SET_RESOLVER);
  return ethRegistry.write.register([label, owner, subregistry, resolver, roles, expiry]);
};