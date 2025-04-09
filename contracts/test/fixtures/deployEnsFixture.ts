import hre from "hardhat";
import { type Address, bytesToHex, keccak256, stringToHex, zeroAddress } from "viem";
import { packetToBytes } from "../utils/utils.js";
import { serveBatchGateway } from '../../lib/ens-contracts/test/fixtures/localBatchGateway.js';

export async function deployEnsFixture() {
  const publicClient = await hre.viem.getPublicClient();
  const accounts = await hre.viem
    .getWalletClients()
    .then((clients) => clients.map((c) => c.account));

  const ALL_ROLES = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffn

  const datastore = await hre.viem.deployContract("RegistryDatastore", []);
  const rootRegistry = await hre.viem.deployContract("PermissionedRegistry", [
    datastore.address,
    zeroAddress,
    ALL_ROLES
  ]);
  const ethRegistry = await hre.viem.deployContract("PermissionedRegistry", [
    datastore.address,
    zeroAddress,
    ALL_ROLES
  ]);
  const bg = await serveBatchGateway();
  after(bg.shutdown);
  const universalResolver = await hre.viem.deployContract("UniversalResolver", [
    rootRegistry.address,
    [bg.localBatchGatewayUrl]
  ]);

  const MAX_EXPIRY = 18446744073709551615n // type(uint64).max
  
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
    [datastoreAddress, metadataAddress ?? zeroAddress, ALL_ROLES],
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
  const ROLE_SET_SUBREGISTRY = 1n << 2n
  const ROLE_SET_RESOLVER = 1n << 3n
  const owner =
    owner_ ?? (await hre.viem.getWalletClients())[0].account.address;
  const roles = (subregistryLocked ? 0n : ROLE_SET_SUBREGISTRY) | (resolverLocked ? 0n : ROLE_SET_RESOLVER);
  return ethRegistry.write.register([label, owner, subregistry, resolver, roles, expiry]);
};