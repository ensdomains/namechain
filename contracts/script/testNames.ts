import { zeroAddress } from "viem";

import type { CrossChainEnvironment } from "./setup.js";

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
    await env.l2.contracts.ethRegistry.write.register([
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
