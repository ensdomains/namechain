import hre from "hardhat";
import { Address, bytesToHex } from "viem";
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
  const ethRegistry = await hre.viem.deployContract("ETHRegistry", [
    datastore.address,
  ]);
  const universalResolver = await hre.viem.deployContract("UniversalResolver", [
    rootRegistry.address,
  ]);

  const rootResource = await rootRegistry.read.ROOT_RESOURCE();
  const ROLE_TLD_ISSUER = await rootRegistry.read.ROLE_TLD_ISSUER();
  const ROLE_REGISTRAR_ROLE = await rootRegistry.read.ROLE_REGISTRAR_ROLE();
  const ROLE_BITMAP_TOKEN_OWNER_DEFAULT = await rootRegistry.read.ROLE_BITMAP_TOKEN_OWNER_DEFAULT();

  await rootRegistry.write.grantRole([
    rootResource,
    ROLE_TLD_ISSUER,
    accounts[0].address,
  ]);

  await ethRegistry.write.grantRole([
    rootResource,
    ROLE_REGISTRAR_ROLE,
    accounts[0].address,
  ]);
  
  await rootRegistry.write.mint([
    "eth",
    accounts[0].address,
    ethRegistry.address,
    1n,
    ROLE_BITMAP_TOKEN_OWNER_DEFAULT,
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
  ownerIndex = 0,
}: {
  name: string;
  parentRegistryAddress: Address;
  datastoreAddress: Address;
  ownerIndex?: number;
}) => {
  const wallet = (await hre.viem.getWalletClients())[ownerIndex];
  return await hre.viem.deployContract(
    "UserRegistry",
    [parentRegistryAddress, bytesToHex(packetToBytes(name)), datastoreAddress],
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
  subregistryLocked = false,
  resolverLocked = false,
}: Pick<EnsFixture, "ethRegistry"> & {
  label: string;
  expiry?: bigint;
  owner?: Address;
  subregistry?: Address;
  subregistryLocked?: boolean;
  resolverLocked?: boolean;
}) => {
  const DEFAULT_ROLE_BITMAP = await ethRegistry.read.ROLE_BITMAP_TOKEN_OWNER_DEFAULT();
  const owner =
    owner_ ?? (await hre.viem.getWalletClients())[0].account.address;
  const flags = (subregistryLocked ? 1n : 0n) | (resolverLocked ? 2n : 0n);
  return ethRegistry.write.register([label, owner, subregistry, flags, DEFAULT_ROLE_BITMAP, expiry]);
};
