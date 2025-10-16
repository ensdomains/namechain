import { zeroAddress, namehash, encodeFunctionData, decodeFunctionResult, parseAbi } from "viem";

import type { CrossChainEnvironment } from "./setup.js";
import { dnsEncodeName } from "../test/utils/utils.js";

const RESOLVER_ABI = parseAbi([
  "function addr(bytes32, uint256 coinType) external view returns (bytes)",
  "function text(bytes32, string key) external view returns (string)",
]);

// DONE
// - Register name
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

    // Get tokenId and owner from L2 registry (for .eth second-level names)
    // Extract label from name (e.g., "test" from "test.eth")
    const label = name.replace('.eth', '');
    let owner = 'N/A';
    let tokenId = 'N/A';
    let expiryDate = 'N/A';

    try {
      const [tid, entry] = await env.l2.contracts.ETHRegistry.read.getNameData([label]);
      tokenId = tid;
      owner = await env.l2.contracts.ETHRegistry.read.ownerOf([tokenId]);
      const expiryTimestamp = Number(entry.expiry);
      expiryDate = expiryTimestamp > 0 ? new Date(expiryTimestamp * 1000).toISOString() : 'Never';
      console.log(`TokenId: ${tokenId}`);
      console.log(`Owner: ${owner}`);
      console.log(`Expiry: ${expiryDate}`);
    } catch (e) {
      console.log(`Could not fetch owner from L2 registry (may be a subname)`);
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

    // Register the name exactly like in urg.test.ts
    await env.l2.contracts.ETHRegistry.write.register([
      label,
      account.address,
      zeroAddress,
      resolver.address,
      0n,
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
