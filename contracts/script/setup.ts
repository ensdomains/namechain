import { artifacts } from "@rocketh";
import { rm } from "node:fs/promises";
import { anvil as createAnvil } from "prool/instances";
import { type Environment, executeDeployScripts, resolveConfig } from "rocketh";
import {
  type Abi,
  type Account,
  type Address,
  type Chain,
  createWalletClient,
  getContract,
  type GetContractReturnType,
  type Hash,
  type Hex,
  publicActions,
  testActions,
  type Transport,
  webSocket,
  zeroAddress,
} from "viem";
import { mnemonicToAccount } from "viem/accounts";

import { serve } from "@namestone/ezccip/serve";
import { WebSocketProvider } from "ethers/providers";
import { Gateway } from "../lib/unruggable-gateways/src/gateway.js";
import { UncheckedRollup } from "../lib/unruggable-gateways/src/UncheckedRollup.js";

import {
  LOCAL_BATCH_GATEWAY_URL,
  MAX_EXPIRY,
  ROLES,
} from "../deploy/constants.js";
import { deployArtifact } from "../test/integration/fixtures/deployArtifact.js";
import {
  computeVerifiableProxyAddress,
  deployVerifiableProxy,
} from "../test/integration/fixtures/deployVerifiableProxy.js";
import { urgArtifact } from "../test/integration/fixtures/externalArtifacts.js";
import { waitForSuccessfulTransactionReceipt } from "../test/utils/waitForSuccessfulTransactionReceipt.ts";
import { patchArtifactsV1 } from "./patchArtifactsV1.js";
import type { RockethArguments, RockethL1Arguments } from "./types.js";
import { getBlock } from "viem/actions";

/**
 * Default chain IDs for devnet environment
 */
export const DEFAULT_L2_CHAIN_ID = 0xeeeeee;
export const DEFAULT_L1_CHAIN_ID = DEFAULT_L2_CHAIN_ID - 1;

type DeployedArtifacts = Record<string, Abi>;

type Future<T> = T | Promise<T>;

// typescript key (see below) mapped to rocketh deploy name
const renames: Record<string, string> = {
  ETHRegistrarV1: "BaseRegistrarImplementation",
  L1BridgeController: "BridgeController",
  L2BridgeController: "BridgeController",
};

const sharedContracts = {
  RegistryDatastore: artifacts.RegistryDatastore.abi,
  SimpleRegistryMetadata: artifacts.SimpleRegistryMetadata.abi,
  HCAFactory: artifacts.MockHCAFactoryBasic.abi,
  VerifiableFactory: artifacts.VerifiableFactory.abi,
  DedicatedResolver: artifacts.DedicatedResolver.abi,
  UserRegistry: artifacts.UserRegistry.abi,
  // common
  MockSurgeNativeBridge: artifacts.MockSurgeNativeBridge.abi,
  ETHRegistry: artifacts.PermissionedRegistry.abi,
  BridgeController: artifacts.BridgeController.abi,
} as const satisfies DeployedArtifacts;

const l1Contracts = {
  ...sharedContracts,
  // v1
  BatchGatewayProvider: artifacts.GatewayProvider.abi,
  RootV1: artifacts.Root.abi,
  ENSRegistryV1: artifacts.ENSRegistry.abi,
  ETHRegistrarV1: artifacts.BaseRegistrarImplementation.abi,
  ReverseRegistrarV1: artifacts.ReverseRegistrar.abi,
  PublicResolverV1: artifacts.PublicResolver.abi,
  NameWrapperV1: artifacts.NameWrapper.abi,
  UniversalResolverV1: artifacts.UniversalResolver.abi,
  // v1 compat
  DefaultReverseRegistrar: artifacts.DefaultReverseRegistrar.abi,
  DefaultReverseResolver: artifacts.DefaultReverseResolver.abi,
  //
  L1SurgeBridge: artifacts.L1SurgeBridge.abi,
  L1BridgeController: artifacts.L1BridgeController.abi,
  UnlockedMigrationController: artifacts.L1UnlockedMigrationController.abi,
  LockedMigrationController: artifacts.L1LockedMigrationController.abi,
  MigratedWrappedNameRegistryImpl: artifacts.MigratedWrappedNameRegistry.abi,
  //
  UniversalResolverV2: artifacts.UniversalResolverV2.abi,
  RootRegistry: artifacts.PermissionedRegistry.abi,
  ETHReverseRegistrar: artifacts.L2ReverseRegistrar.abi,
  ETHReverseResolver: artifacts.ETHReverseResolver.abi,
  ETHSelfResolver: artifacts.DedicatedResolver.abi,
  ETHTLDResolver: artifacts.ETHTLDResolver.abi,
  DNSTLDResolver: artifacts.DNSTLDResolver.abi,
  DNSTXTResolver: artifacts.DNSTXTResolver.abi,
  DNSAliasResolver: artifacts.DNSAliasResolver.abi,
} as const satisfies DeployedArtifacts;

const l2Contracts = {
  ...sharedContracts,
  L2SurgeBridge: artifacts.L2SurgeBridge.abi,
  L2BridgeController: artifacts.L2BridgeController.abi,
  //
  ETHRegistrar: artifacts.ETHRegistrar.abi,
  StandardRentPriceOracle: artifacts.StandardRentPriceOracle.abi,
  MockUSDC: artifacts["test/mocks/MockERC20.sol/MockERC20"].abi,
  MockDAI: artifacts["test/mocks/MockERC20.sol/MockERC20"].abi,
} as const satisfies DeployedArtifacts;

export type CrossChainSnapshot = () => Promise<void>;
export type CrossChainClient = ReturnType<typeof createClient>;
export type CrossChainEnvironment = Awaited<
  ReturnType<typeof setupCrossChainEnvironment>
>;

export type L1Deployment = ChainDeployment<
  typeof l1Contracts,
  typeof l2Contracts
>;
export type L2Deployment = ChainDeployment<
  typeof l2Contracts,
  typeof l1Contracts
>;

function ansi(c: any, s: any) {
  return `\x1b[${c}m${s}\x1b[0m`;
}

function ansiForChain(isL1: boolean) {
  return isL1 ? 36 : 35;
}

function nameForChain(isL1: boolean) {
  return isL1 ? "L1" : "L2";
}

function createClient(transport: Transport, chain: Chain, account: Account) {
  return createWalletClient({
    transport,
    chain,
    account,
    pollingInterval: 50,
    cacheTime: 0, // must be 0 due to client caching
  })
    .extend(publicActions)
    .extend(testActions({ mode: "anvil" }));
}

type SharedContracts = {
  [K in keyof typeof sharedContracts]: (typeof sharedContracts)[K] extends
    | Abi
    | readonly unknown[]
    ? GetContractReturnType<(typeof sharedContracts)[K], CrossChainClient>
    : never;
};
type ContractsOf<A> = {
  [K in keyof A as Exclude<K, keyof typeof sharedContracts>]: A[K] extends
    | Abi
    | readonly unknown[]
    ? GetContractReturnType<A[K], CrossChainClient>
    : never;
};

export class ChainDeployment<
  const A extends typeof sharedContracts &
    DeployedArtifacts = typeof sharedContracts,
  const B extends typeof sharedContracts &
    DeployedArtifacts = typeof sharedContracts,
> {
  readonly contracts: SharedContracts & ContractsOf<A>;
  readonly rx!: ChainDeployment<B, A>;
  constructor(
    readonly isL1: boolean,
    readonly anvil: ReturnType<typeof createAnvil>,
    readonly client: CrossChainClient,
    readonly transport: Transport,
    readonly hostPort: string,
    readonly env: Environment,
    namedArtifacts: A,
  ) {
    // this.deployments = Object.fromEntries(
    //   Object.entries(env.deployments).map(([name, { address }]) => [
    //     name,
    //     address,
    //   ]),
    // );
    this.contracts = Object.fromEntries(
      Object.entries(namedArtifacts).map(([name, abi]) => {
        const deployment = env.get(renames[name] ?? name.replace(/V1$/, ""));
        const contract = getContract({
          abi,
          address: deployment.address,
          client,
        }) as {
          write?: Record<string, (...parameters: unknown[]) => Promise<Hash>>;
        } & Record<string, unknown>;
        if ("write" in contract) {
          const write = contract.write!;
          // override to ensure successful transaction
          // otherwise, success is being assumed based on an eth_estimateGas call
          // but state could change, or eth_estimateGas could be wrong
          contract.write = new Proxy(
            {},
            {
              get(_, functionName: string) {
                return async (...parameters: unknown[]) => {
                  const hash = await write[functionName](...parameters);
                  await waitForSuccessfulTransactionReceipt(client, { hash });
                  return hash;
                };
              },
            },
          );
        }
        return [name, contract];
      }),
    ) as SharedContracts & ContractsOf<A>;
  }
  get name() {
    return nameForChain(this.isL1);
  }
  get arrow() {
    return `${this.name}->${this.rx.name}`;
  }
  async computeVerifiableProxyAddress(args: {
    deployer: Address;
    salt: bigint;
  }) {
    return computeVerifiableProxyAddress({
      factoryAddress: this.contracts.VerifiableFactory.address,
      bytecode: artifacts["UUPSProxy"].bytecode,
      ...args,
    });
  }
  async deployPermissionedRegistry({
    account,
    roles = ROLES.ALL,
  }: {
    account: Account;
    roles?: bigint;
  }) {
    const client = createClient(this.transport, this.client.chain, account);
    const { abi, bytecode } = artifacts.PermissionedRegistry;
    const hash = await client.deployContract({
      abi,
      bytecode,
      args: [
        this.contracts.RegistryDatastore.address,
        this.contracts.HCAFactory.address,
        this.contracts.SimpleRegistryMetadata.address,
        account.address,
        roles,
      ],
    });
    const receipt = await waitForSuccessfulTransactionReceipt(client, {
      hash,
      ensureDeployment: true,
    });
    return getContract({
      abi,
      address: receipt.contractAddress,
      client,
    });
  }
  async deployDedicatedResolver({
    account,
    admin = account.address,
    roles = ROLES.ALL,
    salt,
  }: {
    account: Account;
    admin?: Address;
    roles?: bigint;
    salt?: bigint;
  }) {
    return deployVerifiableProxy({
      walletClient: createClient(this.transport, this.client.chain, account),
      factoryAddress: this.contracts.VerifiableFactory.address,
      implAddress: this.contracts.DedicatedResolver.address,
      abi: this.contracts.DedicatedResolver.abi,
      functionName: "initialize",
      args: [admin, roles],
      salt,
    });
  }
  deployUserRegistry({
    account,
    admin = account.address,
    roles = ROLES.ALL,
    salt,
  }: {
    account: Account;
    admin?: Address;
    roles?: bigint;
    salt?: bigint;
  }) {
    return deployVerifiableProxy({
      walletClient: createClient(this.transport, this.client.chain, account),
      factoryAddress: this.contracts.VerifiableFactory.address,
      implAddress: this.contracts.UserRegistry.address,
      abi: this.contracts.UserRegistry.abi,
      functionName: "initialize",
      args: [admin, roles],
      salt,
    });
  }
}

export async function setupCrossChainEnvironment({
  l2ChainId = DEFAULT_L2_CHAIN_ID,
  l1ChainId = l2ChainId - 1,
  l1Port = 0,
  l2Port = 0,
  urgPort = 0,
  extraAccounts = 5,
  mnemonic = "test test test test test test test test test test test junk",
  saveDeployments = false,
  quiet = !saveDeployments,
  procLog = false,
  extraTime = 0,
}: {
  l1ChainId?: number;
  l2ChainId?: number;
  l1Port?: number;
  l2Port?: number;
  urgPort?: number;
  extraAccounts?: number;
  mnemonic?: string;
  saveDeployments?: boolean;
  quiet?: boolean;
  procLog?: boolean; // show anvil process logs
  extraTime?: number; // extra time to subtract from genesis timestamp
} = {}) {
  // shutdown functions for partial initialization
  const finalizers: (() => unknown | Promise<unknown>)[] = [];
  async function shutdown() {
    await Promise.allSettled(finalizers.map((f) => f()));
  }
  let unquiet = () => {};
  if (quiet) {
    const { log, table } = console;
    console.log = () => {};
    console.table = () => {};
    unquiet = () => {
      console.log = log;
      console.table = table;
    };
  }
  try {
    console.log("Deploying ENSv2...");
    await patchArtifactsV1();

    // list of named wallets
    const names = ["deployer", "owner", "bridger", "user", "user2"];
    extraAccounts += names.length;

    process.env["RUST_LOG"] = "info"; // required to capture console.log()
    const baseArgs = {
      accounts: extraAccounts,
      mnemonic,
      ...(extraTime
        ? { timestamp: Math.floor(Date.now() / 1000) - extraTime }
        : {}),
    };
    const l1Anvil = createAnvil({
      ...baseArgs,
      chainId: l1ChainId,
      port: l1Port,
    });
    const l2Anvil = createAnvil({
      ...baseArgs,
      chainId: l2ChainId,
      port: l2Port,
    });

    // use same accounts on both chains
    const accounts = Array.from({ length: extraAccounts }, (_, i) =>
      Object.assign(mnemonicToAccount(mnemonic, { addressIndex: i }), {
        name: names[i] ?? `unnamed${i}`,
      }),
    );
    const namedAccounts = Object.fromEntries(accounts.map((x) => [x.name, x]));
    const { deployer } = namedAccounts;

    console.log("Launching L1");
    await l1Anvil.start();
    finalizers.push(() => l1Anvil.stop());

    console.log("Launching L2");
    await l2Anvil.start();
    finalizers.push(() => l2Anvil.stop());

    // parse `host:port` from the anvil boot message
    const [l1HostPort, l2HostPort] = [l1Anvil, l2Anvil].map((anvil) => {
      const message = anvil.messages.get().join("\n").trim();
      const match = message.match(/Listening on (.*)$/);
      if (!match) throw new Error(`expected host: ${message}`);
      return match[1];
    });

    [l1Anvil, l2Anvil].forEach((anvil, i) => {
      const isL1 = !i;
      let showConsole = true;
      const log = (chunk: string) => {
        // ref: https://github.com/adraffy/blocksmith.js/blob/main/src/Foundry.js#L991
        const lines = chunk.split("\n").flatMap((line) => {
          if (!line) return [];
          // "2025-10-08T18:08:32.755539Z  INFO node::console: hello world"
          // "2025-10-09T16:21:27.441327Z  INFO node::user: eth_estimateGas"
          // "2025-10-09T16:24:09.289834Z  INFO node::user:     Block Number: 17"
          // "2025-10-09T16:31:48.449325Z  INFO node::user:"
          // "2025-10-09T16:31:48.451639Z  WARN backend: Skipping..."
          const match = line.match(
            /^.{27}  ([A-Z]+) (\w+(?:|::\w+)):(?:$| (.*)$)/,
          );
          if (match) {
            const [, , kind, action] = match;
            if (/^\s*$/.test(action)) return []; // collapse whitespace
            if (kind === "node::user" && /^\w+$/.test(action)) {
              showConsole = action !== "eth_estimateGas"; // detect if inside gas estimation
            }
            if (kind === "node::console") {
              return showConsole ? `${nameForChain(isL1)} ${line}` : []; // ignore console during gas estimation
            }
          }
          if (!procLog) return [];
          return ansi(ansiForChain(isL1), `${nameForChain(isL1)} ${line}`);
        });
        if (!lines.length) return;
        console.log(lines.join("\n"));
      };
      anvil.on("message", log);
      finalizers.push(() => anvil.off("message", log));
    });

    const transportOptions = {
      retryCount: 1,
      keepAlive: true,
      reconnect: false,
      timeout: 10000,
    } as const;
    const l1Transport = webSocket(`ws://${l1HostPort}`, transportOptions);
    const l2Transport = webSocket(`ws://${l2HostPort}`, transportOptions);

    const nativeCurrency = {
      name: "Ether",
      symbol: "ETH",
      decimals: 18,
    } as const;
    const l1Chain: Chain = {
      id: l1ChainId,
      name: "Mainnet (L1)",
      nativeCurrency,
      rpcUrls: { default: { http: [`http://${l1HostPort}`] } },
    };
    const l2Chain: Chain = {
      id: l2ChainId,
      name: "Namechain (L2)",
      nativeCurrency,
      rpcUrls: { default: { http: [`http://${l2HostPort}`] } },
    };

    const l1Client = createClient(l1Transport, l1Chain, deployer);
    const l2Client = createClient(l2Transport, l2Chain, deployer);

    async function deployChain(chain: Chain, args?: RockethArguments) {
      const isL1 = chain.id === l1ChainId;
      const tag = isL1 ? "l1" : "l2";
      const name = `${tag}-local`;
      if (saveDeployments) {
        await rm(new URL(`../deployments/${name}`, import.meta.url), {
          recursive: true,
          force: true,
        });
      }
      process.env.BATCH_GATEWAY_URLS = JSON.stringify([
        LOCAL_BATCH_GATEWAY_URL,
      ]);
      const tags = [tag, "local"];
      const scripts = [`deploy/${tag}`, "deploy/shared"];
      if (isL1) {
        scripts.unshift("lib/ens-contracts/deploy");
        tags.push("use_root"); // deploy root contracts
        tags.push("allow_unsafe"); // tate hacks
        tags.push("legacy"); // legacy registry
      } else {
        scripts.unshift("lib/ens-contracts/deploy/utils/shared/"); // multicall3
      }
      return executeDeployScripts(
        resolveConfig({
          network: {
            nodeUrl: chain.rpcUrls.default.http[0],
            name,
            tags,
            fork: false,
            scripts,
            publicInfo: {
              name,
              nativeCurrency: chain.nativeCurrency,
              rpcUrls: { default: { http: [...chain.rpcUrls.default.http] } },
            },
            pollingInterval: 0.001, // cannot be zero
          },
          askBeforeProceeding: false,
          saveDeployments,
          accounts: Object.fromEntries(
            accounts.map((x) => [x.name, x.address]),
          ),
        }),
        args,
      );
    }

    console.log("Deploying L2");
    const l2Deploy = await deployChain(l2Client.chain);

    console.log("Launching Urg");
    const gateway = new Gateway(
      new UncheckedRollup(
        new WebSocketProvider(`ws://${l2HostPort}`, l2Client.chain.id, {
          staticNetwork: true,
        }),
      ),
    );
    gateway.allowHistorical = true;
    gateway.commitDepth = 0;
    gateway.disableCache();
    const ccip = await serve(gateway, {
      protocol: "raw",
      port: urgPort,
    });
    finalizers.push(ccip.shutdown);

    console.log("Deploying Urg");
    const GatewayVM = await deployArtifact(l1Client, {
      file: urgArtifact("GatewayVM"),
    });
    const hooksAddress = await deployArtifact(l1Client, {
      file: urgArtifact("UncheckedVerifierHooks"),
    });
    const verifierAddress = await deployArtifact(l1Client, {
      file: urgArtifact("UncheckedVerifier"),
      args: [[ccip.endpoint], 0, hooksAddress],
      libs: { GatewayVM },
    });

    console.log("Deploying L1");
    const l1Deploy = await deployChain(l1Client.chain, {
      l2Deploy,
      verifierAddress,
    } satisfies RockethL1Arguments);

    const l1 = new ChainDeployment(
      true,
      l1Anvil,
      l1Client,
      l1Transport,
      l1HostPort,
      l1Deploy,
      l1Contracts,
    );

    const l2 = new ChainDeployment(
      false,
      l2Anvil,
      l2Client,
      l2Transport,
      l2HostPort,
      l2Deploy,
      l2Contracts,
    );

    (l1 as any).rx = l2;
    (l2 as any).rx = l1;

    await setupEnsDotEth(l1, deployer);
    console.log("Setup ens.eth");

    await setupBridgeConfiguration(l1, l2, deployer);
    console.log("Setup bridge configuration");

    console.log("Deployed ENSv2");
    return {
      accounts,
      namedAccounts,
      l1,
      l2,
      urg: {
        gateway,
        gatewayURL: ccip.endpoint,
        verifierAddress,
      },
      sync,
      waitFor,
      getBlocks,
      saveState,
      shutdown,
    };
    // determine the chain of the transaction
    async function findChain(hash: Future<Hex>) {
      return l1Client
        .getTransaction({ hash: await hash })
        .then(() => l1)
        .catch(() => l2);
    }
    async function waitFor(hash: Future<Hex>) {
      hash = await hash;
      const chain = await findChain(hash);
      const receipt = await waitForSuccessfulTransactionReceipt(chain.client, {
        hash,
      });
      return { receipt, chain };
    }
    function getBlocks() {
      return Promise.all([l1Client, l2Client].map((x) => x.getBlock()));
    }
    async function saveState(): Promise<CrossChainSnapshot> {
      const fs = await Promise.all(
        [l1Client, l2Client].map(async (c) => {
          let state = await c.request({ method: "evm_snapshot" } as any);
          let block0 = await c.getBlock();
          return async () => {
            const block1 = await c.getBlock();
            if (block0.stateRoot === block1.stateRoot) return; // noop, assuming no setStorageAt
            const ok = await c.request({
              method: "evm_revert",
              params: [state],
            } as any);
            if (!ok) throw new Error("revert failed");
            // apparently the snapshots cannot be reused
            state = await c.request({ method: "evm_snapshot" } as any);
            block0 = await c.getBlock();
          };
        }),
      );
      return async () => {
        await Promise.all(fs.map((f) => f()));
      };
    }
    async function sync({
      blocks = 1,
      warpSec = "local",
    }: { blocks?: number; warpSec?: number | "local" } = {}) {
      const [t1, t2] = (await getBlocks()).map((x) => Number(x.timestamp));
      let max = Math.max(t1, t2);
      if (warpSec === "local") {
        max = Math.max(max, (Date.now() / 1000) | 0);
      } else {
        max += warpSec;
      }
      await Promise.all([
        l1Client.mine({ blocks, interval: max - t1 }),
        l2Client.mine({ blocks, interval: max - t2 }),
      ]);
      return BigInt(max);
    }
  } catch (err) {
    await shutdown();
    throw err;
  } finally {
    unquiet();
  }
}

async function setupEnsDotEth(l1: L1Deployment, account: Account) {
  // create registry for "ens.eth"
  const ens_ethRegistry = await l1.deployPermissionedRegistry({ account });

  // create "ens.eth"
  await l1.contracts.ETHRegistry.write.register([
    "ens",
    account.address,
    ens_ethRegistry.address,
    zeroAddress,
    0n,
    MAX_EXPIRY,
  ]);

  // create "dnsname.ens.eth"
  // https://etherscan.io/address/0x08769D484a7Cd9c4A98E928D9E270221F3E8578c#code
  await setupNamedResolver(
    "dnsname",
    await deployArtifact(l1.client, {
      file: new URL(
        "../test/integration/l1/dns/ExtendedDNSResolver_53f64de872aad627467a34836be1e2b63713a438.json",
        import.meta.url,
      ),
    }),
  );

  // // create "dnsname2.ens.eth" (was never named?)
  // // https://etherscan.io/address/0x08769D484a7Cd9c4A98E928D9E270221F3E8578c#code
  // await setupNamedResolver(
  //   "dnsname2",
  //   await deployArtifact(l1.client, {
  //     file: new URL(
  //       "../lib/ens-contracts/deployments/mainnet/ExtendedDNSResolver.json",
  //       import.meta.url,
  //     ),
  //   }),
  // );

  // create "dnstxt.ens.eth"
  await setupNamedResolver("dnstxt", l1.contracts.DNSTXTResolver.address);

  // create "dnsalias.ens.eth"
  await setupNamedResolver("dnsalias", l1.contracts.DNSAliasResolver.address);

  async function setupNamedResolver(label: string, address: Address) {
    const resolver = await l1.deployDedicatedResolver({ account });
    await resolver.write.setAddr([60n, address]);
    await ens_ethRegistry.write.register([
      label,
      account.address,
      zeroAddress,
      resolver.address,
      0n,
      MAX_EXPIRY,
    ]);
  }
}

async function setupBridgeConfiguration(
  l1: L1Deployment,
  l2: L2Deployment,
  deployer: Account,
) {
  // Configure bridge relationships for cross-chain messaging
  console.log("Configuring bridge relationships...");
  console.log("L1SurgeBridge:", l1.contracts.L1SurgeBridge.address);
  console.log("L2SurgeBridge:", l2.contracts.L2SurgeBridge.address);
  console.log("L1BridgeController:", l1.contracts.L1BridgeController.address);
  console.log("L2BridgeController:", l2.contracts.L2BridgeController.address);

  // Grant ROLE_SET_BRIDGE to deployer so they can call setBridge
  // ROLE_SET_BRIDGE = 1 << 4 = 16 (from BridgeRolesLib.sol)
  const ROLE_SET_BRIDGE = 1n << 4n;
  await l1.contracts.L1BridgeController.write.grantRootRoles([
    ROLE_SET_BRIDGE,
    deployer.address,
  ]);
  await l2.contracts.L2BridgeController.write.grantRootRoles([
    ROLE_SET_BRIDGE,
    deployer.address,
  ]);

  // Configure bridge controllers to point to their respective bridges
  await l1.contracts.L1BridgeController.write.setBridge([
    l1.contracts.L1SurgeBridge.address,
  ]);
  await l2.contracts.L2BridgeController.write.setBridge([
    l2.contracts.L2SurgeBridge.address,
  ]);

  // Grant bridge roles to the bridges on their respective bridge controllers
  await l1.contracts.L1BridgeController.write.grantRootRoles([
    ROLES.OWNER.BRIDGE.EJECTOR,
    l1.contracts.L1SurgeBridge.address,
  ]);
  await l2.contracts.L2BridgeController.write.grantRootRoles([
    ROLES.OWNER.BRIDGE.EJECTOR,
    l2.contracts.L2SurgeBridge.address,
  ]);

  // Configure destination bridge addresses for cross-chain messaging
  await l1.contracts.L1SurgeBridge.write.setDestBridgeAddress([
    l2.contracts.L2SurgeBridge.address,
  ]);
  await l2.contracts.L2SurgeBridge.write.setDestBridgeAddress([
    l1.contracts.L1SurgeBridge.address,
  ]);

  console.log("✓ Bridge configuration complete");
}
