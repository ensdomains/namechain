import {
  zeroAddress,
  namehash,
  encodeFunctionData,
  decodeFunctionResult,
  parseAbi,
  getContract,
  encodeAbiParameters,
  Address,
} from "viem";

import type { CrossChainEnvironment } from "./setup.js";
import { dnsEncodeName } from "../test/utils/utils.js";
import { ROLES, MAX_EXPIRY } from "../deploy/constants.js";
import { artifacts } from "@rocketh";

const RESOLVER_ABI = parseAbi([
  "function addr(bytes32, uint256 coinType) external view returns (bytes)",
  "function text(bytes32, string key) external view returns (string)",
]);

// ========== Helper Functions ==========

/**
 * Parse an ENS name into its components
 */
function parseName(name: string): {
  label: string;
  parentName: string;
  parts: string[];
  isSecondLevel: boolean;
  tld: string;
} {
  const parts = name.split(".");
  const tld = parts[parts.length - 1];

  if (tld !== "eth") {
    throw new Error(`Name must end with .eth, got: ${name}`);
  }

  return {
    label: parts[0],
    parentName: parts.slice(1).join("."),
    parts,
    isSecondLevel: parts.length === 2,
    tld,
  };
}

/**
 * Create a UserRegistry contract instance
 * @param chain - 'l1' or 'l2' (defaults to 'l2')
 */
function getRegistryContract(
  env: CrossChainEnvironment,
  registryAddress: Address,
  chain: "l1" | "l2" = "l2",
) {
  const client = chain === "l2" ? env.l2.client : env.l1.client;
  return getContract({
    address: registryAddress as `0x${string}`,
    abi: artifacts.UserRegistry.abi,
    client,
  });
}

/**
 * Deploy a dedicated resolver and set default records
 * @param chain - 'l1' or 'l2' to deploy on specific chain
 */
async function deployResolverWithRecords(
  env: CrossChainEnvironment,
  account: any,
  records: {
    description?: string;
    address?: Address;
  },
  chain: "l1" | "l2" = "l2",
) {
  const chainEnv = chain === "l2" ? env.l2 : env.l1;
  const resolver = await chainEnv.deployDedicatedResolver(account);

  // Set ETH address (coin type 60)
  if (records.address) {
    await resolver.write.setAddr([60n, records.address], { account });
  }

  // Set description text record
  if (records.description) {
    await resolver.write.setText(["description", records.description], { account });
  }

  return resolver;
}

// ========== Main Functions ==========

// Helper function to traverse L2 registry hierarchy and get name data
async function traverseL2Registry(
  env: CrossChainEnvironment,
  name: string,
): Promise<{
  owner?: Address;
  expiry?: bigint;
  resolver?: Address;
  subregistry?: Address;
} | null> {
  const nameParts = name.split(".");

  if (nameParts[nameParts.length - 1] !== "eth") {
    return null;
  }

  try {
    let currentRegistryAddress = env.l2.contracts.ETHRegistry.address;
    let tokenId: bigint | undefined;
    let entry: any;

    // Traverse from right to left: e.g., ["sub1", "sub2", "parent", "eth"]
    for (let i = nameParts.length - 2; i >= 0; i--) {
      const label = nameParts[i];

      if (currentRegistryAddress === env.l2.contracts.ETHRegistry.address) {
        // Query ETHRegistry
        [tokenId, entry] = await env.l2.contracts.ETHRegistry.read.getNameData([label]);
        if (i === 0) {
          // This is the final name/subname
          const owner = await env.l2.contracts.ETHRegistry.read.ownerOf([tokenId]);
          return {
            owner,
            expiry: entry.expiry,
            resolver: entry.resolver,
            subregistry: entry.subregistry,
          };
        } else {
          // Move to the subregistry
          currentRegistryAddress = entry.subregistry;
        }
      } else {
        // Query UserRegistry
        const userRegistry = getRegistryContract(env, currentRegistryAddress);
        [tokenId, entry] = await userRegistry.read.getNameData([label]);
        if (i === 0) {
          // This is the final subname
          const owner = await userRegistry.read.ownerOf([tokenId]);
          return {
            owner,
            expiry: entry.expiry,
            resolver: entry.resolver,
            subregistry: entry.subregistry,
          };
        } else {
          // Move to the next subregistry
          currentRegistryAddress = entry.subregistry;
        }
      }
    }
  } catch (e) {
    // Failed to traverse
    return null;
  }

  return null;
}

/**
 * Link a name to appear under a different parent by pointing to the same subregistry.
 * This creates multiple "entry points" into the same child namespace.
 *
 * @param sourceName - The existing name whose subregistry we want to link (e.g., "sub1.sub2.parent.eth")
 * @param targetParentName - The parent under which we want to create a linked entry (e.g., "parent.eth")
 * @param linkLabel - Optional label for the linked name. If not provided, uses the source's label.
 *
 * Example:
 *   linkName(env, "sub1.sub2.parent.eth", "parent.eth")
 *   Creates "sub1.parent.eth" that shares children with "sub1.sub2.parent.eth"
 *
 *   linkName(env, "sub1.sub2.parent.eth", "parent.eth", "linked")
 *   Creates "linked.parent.eth" that shares children with "sub1.sub2.parent.eth"
 */
export async function linkName(
  env: CrossChainEnvironment,
  sourceName: string,
  targetParentName: string,
  linkLabel?: string,
  account = env.namedAccounts.owner,
) {
  console.log(`\nLinking name: ${sourceName} to parent: ${targetParentName}`);

  // 1. Parse and validate source name
  const { label: sourceLabel, parentName: sourceParentName, isSecondLevel } = parseName(sourceName);

  if (isSecondLevel) {
    throw new Error(`Cannot link second-level names directly. Source must be a subname.`);
  }

  // 2. Get source name data and registry
  const sourceData = await traverseL2Registry(env, sourceName);
  if (!sourceData || sourceData.owner === zeroAddress) {
    throw new Error(`Source name ${sourceName} does not exist or has no owner`);
  }

  const sourceParentData = await traverseL2Registry(env, sourceParentName);
  if (!sourceParentData?.subregistry || sourceParentData.subregistry === zeroAddress) {
    throw new Error(`Source parent ${sourceParentName} has no subregistry`);
  }

  const sourceRegistry = getRegistryContract(env, sourceParentData.subregistry);
  const [, sourceEntry] = await sourceRegistry.read.getNameData([sourceLabel]);

  if (sourceEntry.subregistry === zeroAddress) {
    throw new Error(`Source name ${sourceName} has no subregistry to link`);
  }

  console.log(`Source subregistry: ${sourceEntry.subregistry}`);

  // 3. Get target parent data and registry
  const targetParentData = await traverseL2Registry(env, targetParentName);
  if (!targetParentData || targetParentData.owner === zeroAddress) {
    throw new Error(`Target parent ${targetParentName} does not exist`);
  }

  if (!targetParentData.subregistry || targetParentData.subregistry === zeroAddress) {
    throw new Error(`Target parent ${targetParentName} has no subregistry`);
  }

  const targetRegistry = getRegistryContract(env, targetParentData.subregistry);

  // 4. Determine the label for the linked name
  const label = linkLabel || sourceLabel;
  const linkedName = `${label}.${targetParentName}`;

  console.log(`Creating linked name: ${linkedName}`);

  // 5. Check if the label already exists in the target registry
  const [existingTokenId] = await targetRegistry.read.getNameData([label]);
  const existingOwner = await targetRegistry.read.ownerOf([existingTokenId]);

  if (existingOwner !== zeroAddress) {
    console.log(`Warning: ${linkedName} already exists. Updating its subregistry...`);
    await targetRegistry.write.setSubregistry([existingTokenId, sourceEntry.subregistry], { account });
    console.log(`✓ Updated ${linkedName} to point to shared subregistry`);
  } else {
    // 6. Register new entry in target registry with source's subregistry
    console.log(`Deploying resolver for ${linkedName}...`);
    const resolver = await deployResolverWithRecords(env, account, {
      description: `Linked to ${sourceName}`,
      address: account.address,
    });
    console.log(`✓ Resolver deployed at ${resolver.address}`);

    await targetRegistry.write.register(
      [
        label,
        account.address,
        sourceEntry.subregistry, // Key: point to source's subregistry!
        resolver.address,
        ROLES.ALL,
        MAX_EXPIRY,
      ],
      { account },
    );

    console.log(`✓ Registered ${linkedName} with shared subregistry`);
  }

  console.log(`\n✓ Link complete!`);
  console.log(`Children of ${sourceName} and ${linkedName} now resolve to the same place.`);
  console.log(`Example: wallet.${sourceName} and wallet.${linkedName} are the same token.`);
}

// Display name information
export async function showName(env: CrossChainEnvironment, names: string[]) {
  await env.sync();

  const nameData = [];

  for (const name of names) {
    const nameHash = namehash(name);

    // Get owner and expiry info from L2
    const nameParts = name.split(".");
    const isSecondLevel = nameParts.length === 2 && nameParts[1] === "eth";

    let owner: Address | undefined = undefined;
    let expiryDate: string = "N/A";

    const l2Data = await traverseL2Registry(env, name);
    if (l2Data?.owner && l2Data.owner !== zeroAddress) {
      owner = l2Data.owner;
      if (l2Data.expiry) {
        const expiryTimestamp = Number(l2Data.expiry);
        if (l2Data.expiry === MAX_EXPIRY || expiryTimestamp === 0) {
          expiryDate = "Never";
        } else {
          expiryDate = new Date(expiryTimestamp * 1000).toISOString();
        }
      }
    }

    // Check if name exists on L1 or L2 registry for resolver info
    let actualResolver: string | undefined;
    let location: string = "L1";

    if (isSecondLevel) {
      // Try L1 first - if name is on L1, it takes precedence (e.g., bridged names)
      try {
        const label = nameParts[0];
        const [tokenId, entry] =
          await env.l1.contracts.ETHRegistry.read.getNameData([label]);
        const l1Owner = await env.l1.contracts.ETHRegistry.read.ownerOf([tokenId]);

        // Check if it's actually owned on L1 (not zero address)
        if (l1Owner !== zeroAddress) {
          actualResolver = entry.resolver;
          location = "L1";
        } else {
          throw new Error("Not on L1");
        }
      } catch (e) {
        // Not on L1, use L2 data
        if (l2Data?.resolver) {
          actualResolver = l2Data.resolver;
          location = "L2";
        }
      }
    } else {
      // For subnames, use L2 traversal data
      if (l2Data?.resolver) {
        actualResolver = l2Data.resolver;
        location = "L2";
      }
    }

    // Get addr record (coin type 60 - ETH) using L1 UniversalResolver
    const addrCall = encodeFunctionData({
      abi: RESOLVER_ABI,
      functionName: "addr",
      args: [nameHash, 60n],
    });
    const [addrResult] =
      await env.l1.contracts.UniversalResolverV2.read.resolve([
        dnsEncodeName(name),
        addrCall,
      ]);
    const addrBytes = decodeFunctionResult({
      abi: RESOLVER_ABI,
      functionName: "addr",
      data: addrResult,
    }) as string;

    // Get text record (description) using L1 UniversalResolver
    const textCall = encodeFunctionData({
      abi: RESOLVER_ABI,
      functionName: "text",
      args: [nameHash, "description"],
    });
    const [textResult] =
      await env.l1.contracts.UniversalResolverV2.read.resolve([
        dnsEncodeName(name),
        textCall,
      ]);
    const description = decodeFunctionResult({
      abi: RESOLVER_ABI,
      functionName: "text",
      data: textResult,
    }) as string;

    // Truncate addresses to first 7 characters (0x + 5 chars)
    const truncateAddress = (addr: string | undefined) => {
      if (!addr || addr === "0x") return "-";
      return addr.slice(0, 7);
    };

    nameData.push({
      Name: name,
      Owner: truncateAddress(owner),
      Expiry: expiryDate === "Never" ? "Never" : expiryDate.split("T")[0], // Show only date part
      Resolver: `${truncateAddress(actualResolver)} (${location})`,
      Address: truncateAddress(addrBytes),
      Description: description || "-",
    });
  }

  console.log(`\nName Information:`);
  console.table(nameData);
}

// Create a subname (and all parent names if they don't exist)
export async function createSubname(
  env: CrossChainEnvironment,
  fullName: string,
  account = env.namedAccounts.owner,
): Promise<string[]> {
  const createdNames: string[] = [];

  // Parse the name
  const { parts } = parseName(fullName);

  // Start from the parent name (e.g., "parent.eth")
  const parentLabel = parts[parts.length - 2];
  const parentName = `${parentLabel}.eth`;

  console.log(`\nCreating subname: ${fullName}`);
  console.log(`Parent name: ${parentName}`);

  // Get parent tokenId (assumes parent.eth already exists)
  const [parentTokenId] = await env.l2.contracts.ETHRegistry.read.getNameData([
    parentLabel,
  ]);

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
      const [, entry] = await env.l2.contracts.ETHRegistry.read.getNameData([
        parts[i + 1],
      ]);
      subregistryAddress = entry.subregistry;
    } else {
      // Parent is in a UserRegistry
      const parentRegistry = getRegistryContract(env, currentRegistryAddress);
      const [, entry] = await parentRegistry.read.getNameData([parts[i + 1]]);
      subregistryAddress = entry.subregistry;
    }

    // Deploy UserRegistry if it doesn't exist
    if (subregistryAddress === zeroAddress) {
      console.log(`Deploying UserRegistry for ${currentName}...`);

      // Deploy proxy using helper method
      const userRegistry = await env.l2.deployUserRegistry(
        account,
        ROLES.ALL,
        account.address,
      );
      subregistryAddress = userRegistry.address;

      // Set as subregistry on parent
      if (currentRegistryAddress === env.l2.contracts.ETHRegistry.address) {
        await env.l2.contracts.ETHRegistry.write.setSubregistry(
          [currentParentTokenId, subregistryAddress],
          { account },
        );
      } else {
        const parentRegistry = getRegistryContract(env, currentRegistryAddress);
        await parentRegistry.write.setSubregistry(
          [currentParentTokenId, subregistryAddress],
          { account },
        );
      }

      console.log(`✓ UserRegistry deployed at ${subregistryAddress}`);
    }

    // Register the subname in the UserRegistry
    const userRegistry = getRegistryContract(env, subregistryAddress);

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
        console.log(
          `${currentName} exists but is expired, re-registering with MAX_EXPIRY...`,
        );
      } else {
        console.log(`Registering ${currentName}...`);
      }

      // Deploy resolver for this subname
      const resolver = await deployResolverWithRecords(env, account, {
        description: currentName,
        address: account.address,
      });
      console.log(`✓ Resolver deployed at ${resolver.address}`);

      await userRegistry.write.register(
        [
          label,
          account.address,
          zeroAddress, // no nested subregistry yet
          resolver.address,
          ROLES.ALL,
          MAX_EXPIRY,
        ],
        { account },
      );

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
  const label = name.replace(".eth", "");

  // Get current expiry
  const [tokenId, entry] = await env.l2.contracts.ETHRegistry.read.getNameData([
    label,
  ]);

  console.log(`\nRenewing ${name}...`);
  if (entry.expiry === MAX_EXPIRY) {
    console.log(`Current expiry: Never (MAX_EXPIRY)`);
  } else {
    const currentExpiry = Number(entry.expiry);
    console.log(
      `Current expiry: ${new Date(currentExpiry * 1000).toISOString()}`,
    );
  }
  console.log(`Extending by: ${durationInDays} days`);

  const duration = BigInt(durationInDays * 24 * 60 * 60); // Convert days to seconds
  const paymentToken = env.l2.contracts.MockUSDC.address;
  const referrer =
    "0x0000000000000000000000000000000000000000000000000000000000000000";

  // Approve payment token (get price first to know how much to approve)
  const [price] = await env.l2.contracts.ETHRegistrar.read.rentPrice([
    label,
    account.address,
    duration,
    paymentToken,
  ]);

  console.log(`Renewal price: ${price}`);

  // Mint tokens if needed
  const balance = await env.l2.contracts.MockUSDC.read.balanceOf([
    account.address,
  ]);
  console.log(`Current balance: ${balance}`);

  if (balance < price) {
    const amountToMint = price - balance + 1000000n; // Mint a bit extra
    console.log(`Minting ${amountToMint} tokens...`);
    await env.l2.contracts.MockUSDC.write.mint(
      [account.address, amountToMint],
      { account },
    );
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

  const [, newEntry] = await env.l2.contracts.ETHRegistry.read.getNameData([
    label,
  ]);
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
  const label = name.replace(".eth", "");

  // Get tokenId from registry
  const [tokenId] = await env.l2.contracts.ETHRegistry.read.getNameData([
    label,
  ]);

  console.log(`\nTransferring ${name}...`);
  console.log(`TokenId: ${tokenId}`);
  console.log(`From: ${account.address}`);
  console.log(`To: ${newOwner}`);

  // Transfer the token (roles should already be granted during registration)
  await env.l2.contracts.ETHRegistry.write.safeTransferFrom(
    [account.address, newOwner, tokenId, 1n, "0x"],
    { account },
  );

  console.log(`✓ Transfer completed`);
}

// Change roles for a name on L2
export async function changeRole(
  env: CrossChainEnvironment,
  name: string,
  targetAccount: string,
  rolesToGrant: bigint,
  rolesToRevoke: bigint,
  account = env.namedAccounts.owner,
) {
  // Extract label from name
  const label = name.replace(".eth", "");

  // Get tokenId from registry
  const [tokenId] = await env.l2.contracts.ETHRegistry.read.getNameData([
    label,
  ]);

  console.log(`\nChanging roles for ${name}...`);
  console.log(`TokenId (before): ${tokenId}`);
  console.log(`Target Account: ${targetAccount}`);
  console.log(`Roles to Grant: ${rolesToGrant}`);
  console.log(`Roles to Revoke: ${rolesToRevoke}`);

  // Get current roles
  const currentRoles = await env.l2.contracts.ETHRegistry.read.roles([
    tokenId,
    targetAccount,
  ]);
  console.log(`Current Roles: ${currentRoles}`);

  // Grant roles if specified
  if (rolesToGrant > 0n) {
    await env.l2.contracts.ETHRegistry.write.grantRoles(
      [tokenId, rolesToGrant, targetAccount],
      { account },
    );
    console.log(`✓ Granted roles: ${rolesToGrant}`);
  }

  // Revoke roles if specified
  if (rolesToRevoke > 0n) {
    await env.l2.contracts.ETHRegistry.write.revokeRoles(
      [tokenId, rolesToRevoke, targetAccount],
      { account },
    );
    console.log(`✓ Revoked roles: ${rolesToRevoke}`);
  }

  // Get new tokenId to check if it changed
  const [newTokenId] = await env.l2.contracts.ETHRegistry.read.getNameData([
    label,
  ]);

  // Get new roles
  const newRoles = await env.l2.contracts.ETHRegistry.read.roles([
    newTokenId,
    targetAccount,
  ]);

  console.log(`TokenId (after): ${newTokenId}`);
  console.log(`New Roles: ${newRoles}`);
  console.log(
    `TokenId changed: ${tokenId !== newTokenId ? "YES" : "NO"}`,
  );

  console.log(`✓ Role change completed`);
}

// Bridge (eject) a name from L2 to L1 and update its text record
export async function bridgeName(
  env: CrossChainEnvironment,
  name: string,
  account = env.namedAccounts.owner,
) {
  console.log(`\nBridging ${name} from L2 to L1...`);

  const label = name.replace(".eth", "");

  // Get name data from L2
  const [tokenId, entry] = await env.l2.contracts.ETHRegistry.read.getNameData([
    label,
  ]);
  const owner = await env.l2.contracts.ETHRegistry.read.ownerOf([tokenId]);

  console.log(`TokenId: ${tokenId}`);
  console.log(`Owner: ${owner}`);
  console.log(`L2 Resolver: ${entry.resolver}`);

  // Step 1: Deploy a new resolver on L1 FIRST (before bridging)
  console.log(`Deploying new resolver on L1...`);
  const l1Resolver = await env.l1.deployDedicatedResolver(account);
  console.log(`✓ Resolver deployed at ${l1Resolver.address}`);

  // DNS encode the label (use dnsEncodeName utility)
  const dnsEncodedName = dnsEncodeName(name);

  // Encode TransferData struct - use the L1 resolver we just deployed
  const encodedTransferData = encodeAbiParameters(
    [
      {
        name: "transferData",
        type: "tuple",
        components: [
          { name: "dnsEncodedName", type: "bytes" },
          { name: "owner", type: "address" },
          { name: "subregistry", type: "address" },
          { name: "resolver", type: "address" },
          { name: "roleBitmap", type: "uint256" },
          { name: "expires", type: "uint64" },
        ],
      },
    ],
    [
      {
        dnsEncodedName,
        owner: account.address,
        subregistry: entry.subregistry,
        resolver: l1Resolver.address, // Use L1 resolver instead of L2 resolver
        roleBitmap: ROLES.ALL,
        expires: entry.expiry,
      },
    ],
  );

  // Step 2: Transfer name to L2BridgeController (this initiates ejection)
  await env.waitFor(
    env.l2.contracts.ETHRegistry.write.safeTransferFrom(
      [
        account.address,
        env.l2.contracts.BridgeController.address,
        tokenId,
        1n,
        encodedTransferData,
      ],
      { account },
    ),
  );

  console.log(`✓ Name ejected from L2`);

  // Step 3: Simulate bridge message delivery
  // In real scenario, this would be handled by the bridge infrastructure
  // For testing, we manually call the L1 bridge controller

  console.log(`✓ Name registered on L1`);

  // Step 4: Set text record on the L1 resolver (DedicatedResolver only takes key and value)
  await l1Resolver.write.setText(
    ["description", `${label}.eth (bridged to L1)`],
    { account },
  );

  console.log(
    `✓ Updated text record on L1: Default test name: ${label}.eth (bridged to L1)`,
  );
}

// Register default test names on L2
export async function registerTestNames(
  env: CrossChainEnvironment,
  labels: string[],
  account = env.namedAccounts.owner,
) {
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
      ["description", `${label}.eth`],
      { account },
    );
  }
}
