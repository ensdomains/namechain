import { zeroAddress, namehash, encodeFunctionData, decodeFunctionResult, parseAbi, getContract, encodeAbiParameters } from "viem";

import type { CrossChainEnvironment } from "./setup.js";
import { dnsEncodeName } from "../test/utils/utils.js";
import { ROLES, MAX_EXPIRY } from "../deploy/constants.js";
import { artifacts } from "@rocketh";

const RESOLVER_ABI = parseAbi([
  "function addr(bytes32, uint256 coinType) external view returns (bytes)",
  "function text(bytes32, string key) external view returns (string)",
]);

// TODO
// set reverse record
// show owner and expiry for subname (need to traverse registries)
// expire name (wait for expiry, then show expired, then re-register)

// DONE
// - Register name
// - Transfer ownership
// - Renew name
// - Bridge name
// - Set resolver
// - Set addr record
// - Set text record
// - Show a function that shows the owner of a name
// - Show a function that shows the addr record of a name
// - Show a function that shows the text record of a name

// Display name information
export async function showName(
  env: CrossChainEnvironment,
  names: string[],
) {
  for (const name of names) {
    const nameHash = namehash(name); // This is already bytes32 (hex string)

    console.log(`\nFetching information for: ${name}`);
    console.log(`NameHash: ${nameHash}`);

    // Get owner and expiry info
    // For second-level names (e.g., "test.eth"), query ETHRegistry directly
    // For subnames (e.g., "sub.test.eth"), we'd need to traverse the registry hierarchy
    const nameParts = name.split('.');
    const isSecondLevel = nameParts.length === 2 && nameParts[1] === 'eth';

    let owner = 'N/A';
    let tokenId = 'N/A';
    let expiryDate = 'N/A';

    if (isSecondLevel) {
      try {
        const label = nameParts[0];
        const [tid, entry] = await env.l2.contracts.ETHRegistry.read.getNameData([label]);
        tokenId = tid;
        owner = await env.l2.contracts.ETHRegistry.read.ownerOf([tokenId]);
        const expiryTimestamp = Number(entry.expiry);
        // MAX_EXPIRY is too large for JavaScript Date, treat as 'Never'
        if (entry.expiry === MAX_EXPIRY || expiryTimestamp === 0) {
          expiryDate = 'Never';
        } else {
          expiryDate = new Date(expiryTimestamp * 1000).toISOString();
        }
        console.log(`TokenId: ${tokenId}`);
        console.log(`Owner: ${owner}`);
        console.log(`Expiry: ${expiryDate}`);
      } catch (e) {
        console.log(`Could not fetch owner from L2 registry`);
      }
    } else {
      console.log(`Subname detected - owner info not shown (would require registry traversal)`);
    }

    // Get resolver address using L1 UniversalResolver
    const [resolver] = await env.l1.contracts.UniversalResolverV2.read.findResolver([
      dnsEncodeName(name),
    ]);
    console.log(`Resolver: ${resolver}`);

    // Get addr record (coin type 60 - ETH) using L1 UniversalResolver
    // L1 UR will use Unruggable Gateway to fetch from L2
    const addrCall = encodeFunctionData({
      abi: RESOLVER_ABI,
      functionName: "addr",
      args: [nameHash, 60n],
    });
    const [addrResult] = await env.l1.contracts.UniversalResolverV2.read.resolve([
      dnsEncodeName(name),
      addrCall,
    ]);
    const addrBytes = decodeFunctionResult({
      abi: RESOLVER_ABI,
      functionName: "addr",
      data: addrResult,
    });

    // Get text record (description) using L1 UniversalResolver
    const textCall = encodeFunctionData({
      abi: RESOLVER_ABI,
      functionName: "text",
      args: [nameHash, "description"],
    });
    const [textResult] = await env.l1.contracts.UniversalResolverV2.read.resolve([
      dnsEncodeName(name),
      textCall,
    ]);
    const description = decodeFunctionResult({
      abi: RESOLVER_ABI,
      functionName: "text",
      data: textResult,
    });
    console.log(`\nName Information for ${name}:`);
    console.table({
      Name: name,
      Owner: owner,
      Expiry: expiryDate,
      Resolver: resolver,
      "Address (coin type 60)": addrBytes,
      Description: description || "(not set)",
    });
  }
}

// Create a subname (and all parent names if they don't exist)
export async function createSubname(
  env: CrossChainEnvironment,
  fullName: string,
  account = env.namedAccounts.owner,
): Promise<string[]> {
  const createdNames: string[] = [];

  // Parse the name into parts (e.g., "sub1.sub2.parent.eth" -> ["sub1", "sub2", "parent", "eth"])
  const parts = fullName.split('.');

  if (parts[parts.length - 1] !== 'eth') {
    throw new Error('Name must end with .eth');
  }

  // Start from the parent name (e.g., "parent.eth")
  const parentLabel = parts[parts.length - 2];
  const parentName = `${parentLabel}.eth`;

  console.log(`\nCreating subname: ${fullName}`);
  console.log(`Parent name: ${parentName}`);

  // Get parent tokenId (assumes parent.eth already exists)
  const [parentTokenId] = await env.l2.contracts.ETHRegistry.read.getNameData([parentLabel]);

  // For each level of subnames, create UserRegistry and register
  let currentParentTokenId = parentTokenId;
  let currentRegistryAddress = env.l2.contracts.ETHRegistry.address;
  let currentName = parentName;

  // Process subname parts from right to left (parent to child)
  // e.g., for "sub1.sub2.parent.eth", process in order: sub2, sub1
  for (let i = parts.length - 3; i >= 0; i--) {
    const label = parts[i];
    currentName = `${label}.${currentName}`;

    console.log(`\nProcessing level: ${currentName}`);

    // Check if current parent has a subregistry
    let subregistryAddress: string;

    if (currentRegistryAddress === env.l2.contracts.ETHRegistry.address) {
      // Parent is in ETHRegistry
      const [, entry] = await env.l2.contracts.ETHRegistry.read.getNameData([parts[i + 1]]);
      subregistryAddress = entry.subregistry;
    } else {
      // Parent is in a UserRegistry
      const parentRegistry = getContract({
        address: currentRegistryAddress as `0x${string}`,
        abi: artifacts.UserRegistry.abi,
        client: env.l2.client,
      });
      const [, entry] = await parentRegistry.read.getNameData([parts[i + 1]]);
      subregistryAddress = entry.subregistry;
    }

    // Deploy UserRegistry if it doesn't exist
    if (subregistryAddress === zeroAddress) {
      console.log(`Deploying UserRegistry for ${currentName}...`);

      // Deploy proxy using helper method
      const userRegistry = await env.l2.deployUserRegistry(account, ROLES.ALL, account.address);
      subregistryAddress = userRegistry.address;

      // Set as subregistry on parent
      if (currentRegistryAddress === env.l2.contracts.ETHRegistry.address) {
        await env.l2.contracts.ETHRegistry.write.setSubregistry(
          [currentParentTokenId, subregistryAddress],
          { account }
        );
      } else {
        const parentRegistry = getContract({
          address: currentRegistryAddress as `0x${string}`,
          abi: artifacts.UserRegistry.abi,
          client: env.l2.client,
        });
        await parentRegistry.write.setSubregistry(
          [currentParentTokenId, subregistryAddress],
          { account }
        );
      }

      console.log(`✓ UserRegistry deployed at ${subregistryAddress}`);
    }

    // Register the subname in the UserRegistry
    const userRegistry = getContract({
      address: subregistryAddress as `0x${string}`,
      abi: artifacts.UserRegistry.abi,
      client: env.l2.client,
    });

    // Check if already registered and if it's expired
    const [tokenId, entry] = await userRegistry.read.getNameData([label]);
    const owner = await userRegistry.read.ownerOf([tokenId]);
    const alreadyExists = owner !== zeroAddress;

    // Check if expired
    const currentTime = BigInt(Math.floor(Date.now() / 1000));
    const isExpired = alreadyExists && entry.expiry < currentTime;

    if (alreadyExists && !isExpired) {
      console.log(`✓ ${currentName} already exists and is not expired`);
    } else {
      if (isExpired) {
        console.log(`${currentName} exists but is expired, re-registering with MAX_EXPIRY...`);
      } else {
        console.log(`Registering ${currentName}...`);
      }

      // Deploy resolver for this subname
      const resolver = await env.l2.deployDedicatedResolver(account);

      await userRegistry.write.register(
        [
          label,
          account.address,
          zeroAddress, // no nested subregistry yet
          resolver.address,
          ROLES.ALL,
          MAX_EXPIRY,
        ],
        { account }
      );

      // Set some default records
      await resolver.write.setAddr([60n, account.address], { account });
      await resolver.write.setText(["description", `Subname: ${currentName}`], { account });

      console.log(`✓ Registered ${currentName}`);
      createdNames.push(currentName);
    }

    // Update for next iteration
    currentParentTokenId = tokenId;
    currentRegistryAddress = subregistryAddress;
  }

  console.log(`\n✓ Created ${createdNames.length} new name(s)`);
  return createdNames;
}

// Renew a name on L2
export async function renewName(
  env: CrossChainEnvironment,
  name: string,
  durationInDays: number,
  account = env.namedAccounts.owner,
) {
  // Extract label from name
  const label = name.replace('.eth', '');

  // Get current expiry
  const [tokenId, entry] = await env.l2.contracts.ETHRegistry.read.getNameData([label]);

  console.log(`\nRenewing ${name}...`);
  if (entry.expiry === MAX_EXPIRY) {
    console.log(`Current expiry: Never (MAX_EXPIRY)`);
  } else {
    const currentExpiry = Number(entry.expiry);
    console.log(`Current expiry: ${new Date(currentExpiry * 1000).toISOString()}`);
  }
  console.log(`Extending by: ${durationInDays} days`);

  const duration = BigInt(durationInDays * 24 * 60 * 60); // Convert days to seconds
  const paymentToken = env.l2.contracts.MockUSDC.address;
  const referrer = '0x0000000000000000000000000000000000000000000000000000000000000000';

  // Approve payment token (get price first to know how much to approve)
  const [price] = await env.l2.contracts.ETHRegistrar.read.rentPrice([
    label,
    account.address,
    duration,
    paymentToken,
  ]);

  console.log(`Renewal price: ${price}`);

  // Mint tokens if needed
  const balance = await env.l2.contracts.MockUSDC.read.balanceOf([account.address]);
  console.log(`Current balance: ${balance}`);

  if (balance < price) {
    const amountToMint = price - balance + 1000000n; // Mint a bit extra
    console.log(`Minting ${amountToMint} tokens...`);
    await env.l2.contracts.MockUSDC.write.mint([account.address, amountToMint], { account });
  }

  // Approve the registrar to spend tokens
  await env.l2.contracts.MockUSDC.write.approve(
    [env.l2.contracts.ETHRegistrar.address, price],
    { account },
  );

  // Renew the name
  await env.l2.contracts.ETHRegistrar.write.renew(
    [label, duration, paymentToken, referrer],
    { account },
  );

  const [, newEntry] = await env.l2.contracts.ETHRegistry.read.getNameData([label]);
  const newExpiry = Number(newEntry.expiry);
  console.log(`New expiry: ${new Date(newExpiry * 1000).toISOString()}`);
  console.log(`✓ Renewal completed`);
}

// Transfer a name to a new owner on L2
export async function transferName(
  env: CrossChainEnvironment,
  name: string,
  newOwner: string,
  account = env.namedAccounts.owner,
) {
  // Extract label from name
  const label = name.replace('.eth', '');

  // Get tokenId from registry
  const [tokenId] = await env.l2.contracts.ETHRegistry.read.getNameData([label]);

  console.log(`\nTransferring ${name}...`);
  console.log(`TokenId: ${tokenId}`);
  console.log(`From: ${account.address}`);
  console.log(`To: ${newOwner}`);

  // Transfer the token (roles should already be granted during registration)
  await env.l2.contracts.ETHRegistry.write.safeTransferFrom(
    [account.address, newOwner, tokenId, 1n, '0x'],
    { account },
  );

  console.log(`✓ Transfer completed`);
}

// Bridge (eject) a name from L2 to L1 and update its text record
export async function bridgeName(
  env: CrossChainEnvironment,
  name: string,
  account = env.namedAccounts.owner,
) {
  console.log(`\nBridging ${name} from L2 to L1...`);

  const label = name.replace('.eth', '');

  // Get name data from L2
  const [tokenId, entry] = await env.l2.contracts.ETHRegistry.read.getNameData([label]);
  const owner = await env.l2.contracts.ETHRegistry.read.ownerOf([tokenId]);

  console.log(`TokenId: ${tokenId}`);
  console.log(`Owner: ${owner}`);
  console.log(`Resolver: ${entry.resolver}`);

  // DNS encode the label (use dnsEncodeName utility)
  const dnsEncodedName = dnsEncodeName(name);

  // Encode TransferData struct
  const encodedTransferData = encodeAbiParameters(
    [{ type: 'bytes' }, { type: 'address' }, { type: 'address' }, { type: 'address' }, { type: 'uint256' }, { type: 'uint64' }],
    [dnsEncodedName, account.address, entry.subregistry, entry.resolver, ROLES.ALL, entry.expiry]
  );

  // Step 1: Transfer name to L2BridgeController (this initiates ejection)
  await env.l2.contracts.ETHRegistry.write.safeTransferFrom(
    [account.address, env.l2.contracts.BridgeController.address, tokenId, 1n, encodedTransferData],
    { account },
  );

  console.log(`✓ Name ejected from L2`);

  // Step 2: Simulate bridge message delivery
  // In real scenario, this would be handled by the bridge infrastructure
  // For testing, we manually call the L1 bridge controller

  // Wait a bit for the mock bridge to process
  await new Promise(resolve => setTimeout(resolve, 100));

  console.log(`✓ Name registered on L1`);

  // Step 3: Deploy a new resolver on L1 and update the name
  console.log(`Deploying new resolver on L1...`);
  const l1Resolver = await env.l1.deployDedicatedResolver(account);
  console.log(`✓ Resolver deployed at ${l1Resolver.address}`);

  // Set the new resolver on L1 (using tokenId, not label)
  await env.l1.contracts.ETHRegistry.write.setResolver(
    [tokenId, l1Resolver.address],
    { account }
  );
  console.log(`✓ Resolver set on L1`);

  // Set text record on the new L1 resolver (DedicatedResolver only takes key and value)
  await l1Resolver.write.setText(
    ["description", `Default test name: ${label}.eth (bridged to L1)`],
    { account },
  );

  console.log(`✓ Updated text record on L1: Default test name: ${label}.eth (bridged to L1)`);
}

// Register default test names on L2
export async function registerTestNames(
  env: CrossChainEnvironment,
  labels: string[],
  account = env.namedAccounts.owner,
) {
  const created = [];
  for (const label of labels) {
    // Deploy a dedicated resolver for this name (same as test)
    const resolver = await env.l2.deployDedicatedResolver(account);

    // Register the name with all roles (including transfer role)
    await env.l2.contracts.ETHRegistry.write.register([
      label,
      account.address,
      zeroAddress,
      resolver.address,
      ROLES.ALL,
      BigInt(Math.floor(Date.now() / 1000) + 86400),
    ]);

    // Set some default records
    await resolver.write.setAddr(
      [
        60n, // ETH coin type
        account.address,
      ],
      { account },
    );
    await resolver.write.setText(
      ["description", `Default test name: ${label}.eth`],
      { account },
    );

    created.push({ name: `${label}.eth`, resolver: resolver.address });
  }
  console.log(`\nL2 Names for Owner: ${account.address}:`);
  console.table(created);
}
