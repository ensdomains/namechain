import hre from "hardhat";
import { type Address, bytesToHex, keccak256, stringToHex, zeroAddress } from "viem";
import { packetToBytes } from "../utils/utils.js";

export async function deployEnsFixture() {
  const publicClient = await hre.viem.getPublicClient();
  const accounts = await hre.viem
    .getWalletClients()
    .then((clients) => clients.map((c) => c.account));

  const datastore = await hre.viem.deployContract("RegistryDatastore", []);
  const rootRegistry = await hre.viem.deployContract("RootRegistry", [
    datastore.address,
  ]);
  const metadata = await hre.viem.deployContract("SimpleRegistryMetadata", []);
  const ethRegistry = await hre.viem.deployContract("ETHRegistry", [
    datastore.address,
    metadata.address,
  ]);
  const universalResolver = await hre.viem.deployContract("UniversalResolver", [
    rootRegistry.address,
  ]);

  const [ROLE_SET_SUBREGISTRY, ROLE_SET_RESOLVER] = await Promise.all([
    rootRegistry.read.ROLE_SET_SUBREGISTRY(),
    rootRegistry.read.ROLE_SET_RESOLVER(),
  ]);
  
  await rootRegistry.write.mint([
    "eth",
    accounts[0].address,
    ethRegistry.address,
    1n,
    ROLE_SET_SUBREGISTRY | ROLE_SET_RESOLVER,
    "https://example.com/"
  ]);

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
    "UserRegistry",
    [parentRegistryAddress, bytesToHex(packetToBytes(name)), datastoreAddress, metadataAddress ?? zeroAddress],
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
  const flags = (subregistryLocked ? 1n : 0n) | (resolverLocked ? 2n : 0n);
  return ethRegistry.write.register([label, owner, subregistry, resolver, flags, ROLE_SET_SUBREGISTRY | ROLE_SET_RESOLVER, expiry]);
};
