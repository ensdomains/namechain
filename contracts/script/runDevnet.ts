import {
  zeroHash,
  zeroAddress,
  type Address,
  encodeFunctionData,
  decodeFunctionResult,
} from "viem";
import { createMockRelay } from "./mockRelay.js";
import { setupCrossChainEnvironment } from "./setup.js";
import { dnsEncodeName } from "../test/utils/utils.ts";
import { artifacts } from "@rocketh";

const env = await setupCrossChainEnvironment();

process.on("SIGINT", async () => {
  console.log("\nShutting down...");
  await env.shutdown();
  process.exit();
});

createMockRelay({
  l1Bridge: env.l1.contracts.mockBridge,
  l2Bridge: env.l2.contracts.mockBridge,
  l1Client: env.l1.client,
  l2Client: env.l2.client,
});

console.log("\nAvailable Test Accounts:");
console.log("========================");

console.log("\nL1 and L2 Chain Test Accounts:");
console.log(Object.fromEntries(env.accounts.map((x, i) => [i + 1, x.address])));

console.log("\nDeployments:");
console.log("============");

console.log({
  urg: (({ gateway, ...a }) => a)(env.urg),
  l1: dump(env.l1),
  l2: dump(env.l2),
});

function dump(deployment: typeof env.l1 | typeof env.l2) {
  const { client, hostPort, contracts, ...rest } = deployment;
  return {
    chain: client.chain.id,
    endpoint: `{http,ws}://${hostPort}`,
    contracts: extractAddresses(contracts),
    //...rest,
  };
}

function extractAddresses(obj: Record<string, { address: Address }>) {
  return Object.fromEntries(
    Object.entries(obj).map(([k, v]) => [k, v.address]),
  );
}

try {
  const owner = env.accounts[0];

  const resolver = await env.l2.deployDedicatedResolver(owner);
  await resolver.write.setText(["avatar", "chonk"]);

  await env.l2.contracts.ethRegistry.write.register([
    "chonk",
    owner.address,
    zeroAddress,
    resolver.address,
    0n,
    BigInt(Math.floor(Date.now() / 1000) + 10000),
  ]);

  const [answer] = await env.l1.contracts.universalResolver.read.resolve([
    dnsEncodeName("chonk.eth"),
    encodeFunctionData({
      abi: artifacts.ITextResolver.abi,
      functionName: "text",
      args: [zeroHash, "avatar"],
    }),
  ]);

  const value = decodeFunctionResult({
    abi: artifacts.ITextResolver.abi,
    functionName: "text",
    data: answer,
  });

  console.log({ value });
} catch (err) {
  console.log(err);
}
