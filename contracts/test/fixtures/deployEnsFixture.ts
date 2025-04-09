import hre from "hardhat";
import { type Address, zeroAddress } from "viem";
import { serveBatchGateway } from "../../lib/ens-contracts/test/fixtures/localBatchGateway.js";

export const ALL_ROLES = (1n << 256n) - 1n;
export const MAX_EXPIRY = (1n << 64n) - 1n;

export async function deployEnsFixture(enableCcipRead = false) {
	const publicClient = await hre.viem.getPublicClient();
	const accounts = await hre.viem
		.getWalletClients()
		.then((clients) => clients.map((c) => c.account));

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

	const gateways: string[] = [];
	if (enableCcipRead) {
		const bg = await serveBatchGateway();
		after(bg.shutdown);
		gateways.push(bg.localBatchGatewayUrl);
	}
	const universalResolver = await hre.viem.deployContract(
		"UniversalResolver",
		[rootRegistry.address, gateways],
		enableCcipRead
			? {
					client: {
						public: await hre.viem.getPublicClient({
							ccipRead: undefined,
						}),
					},
			  }
			: undefined
	);

	await rootRegistry.write.register([
		"eth",
		accounts[0].address,
		ethRegistry.address,
		zeroAddress,
		ALL_ROLES,
		MAX_EXPIRY,
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
		}
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
