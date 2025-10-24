import { anvil as createAnvil } from "prool/instances";
import { type Environment, executeDeployScripts, resolveConfig } from "rocketh";
import {
  createWalletClient,
  getContract,
  webSocket,
  publicActions,
  testActions,
  zeroAddress,
  encodeFunctionData,
  type Account,
  type Chain,
  type GetContractReturnType,
  type Transport,
  type Abi,
  Hex,
} from "viem";
import { mnemonicToAccount } from "viem/accounts";
import { artifacts } from "@rocketh";
import { rm } from "node:fs/promises";

import { serve } from "@namestone/ezccip/serve";
import { WebSocketProvider } from "ethers/providers";
import { Gateway } from "../lib/unruggable-gateways/src/gateway.js";
import { UncheckedRollup } from "../lib/unruggable-gateways/src/UncheckedRollup.js";

import type { RockethL1Arguments, RockethArguments } from "./types.js";
import { deployArtifact } from "../test/integration/fixtures/deployArtifact.js";
import { deployVerifiableProxy } from "../test/integration/fixtures/deployVerifiableProxy.js";
import { urgArtifact } from "../test/integration/fixtures/externalArtifacts.js";
import { patchArtifactsV1 } from "./patchArtifactsV1.js";
import {
  LOCAL_BATCH_GATEWAY_URL,
  MAX_EXPIRY,
  ROLES,
} from "../deploy/constants.js";

type DeployedArtifacts = Record<string, Abi>;

type Future<T> = T | Promise<T>;

// typescript key (see below) mapped to rocketh deploy name
const renames: Record<string, string> = {
  ETHRegistrarV1: "BaseRegistrarImplementation",
  MockL1Bridge: "MockBridge",
  MockL2Bridge: "MockBridge",
  L1BridgeController: "BridgeController",
  L2BridgeController: "BridgeController",
};

const sharedContracts = {
  RegistryDatastore: artifacts.RegistryDatastore.abi,
  SimpleRegistryMetadata: artifacts.SimpleRegistryMetadata.abi,
  VerifiableFactory: artifacts.VerifiableFactory.abi,
  DedicatedResolverImpl: artifacts.DedicatedResolver.abi,
  UserRegistryImpl: artifacts.UserRegistry.abi,
  // common
  MockBridge: artifacts.MockBridgeBase.abi,
  ETHRegistry: artifacts.PermissionedRegistry.abi,
  BridgeController: artifacts.EjectionController.abi,
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
  MockL1Bridge: artifacts.MockL1Bridge.abi,
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
  MockL2Bridge: artifacts.MockL2Bridge.abi,
  L2BridgeController: artifacts.L2BridgeController.abi,
  //
  ETHRegistrar: artifacts.ETHRegistrar.abi,
  StandardRentPriceOracle: artifacts.StandardRentPriceOracle.abi,
  MockUSDC: artifacts["test/mocks/MockERC20.sol/MockERC20"].abi,
  MockDAI: artifacts["test/mocks/MockERC20.sol/MockERC20"].abi,
} as const satisfies DeployedArtifacts;

export type CrossChainSnapshot = () => Promise<void>;
export type CrossChainEnvironment = Awaited<
  ReturnType<typeof setupCrossChainEnvironment>
>;

export type L1Deployment = ChainDeployment<typeof l1Contracts>;
export type L2Deployment = ChainDeployment<typeof l2Contracts>;

export type CrossChainClient = ReturnType<typeof createClient>;

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
    pollingInterval: 0,
    cacheTime: 0, // must be 0 due to client caching
  })
    .extend(publicActions)
    .extend(testActions({ mode: "anvil" }));
}

export class ChainDeployment<
  A extends DeployedArtifacts = typeof sharedContracts,
  B extends DeployedArtifacts = typeof sharedContracts,
> {
  readonly contracts: {
    [K in keyof A]: GetContractReturnType<A[K], CrossChainClient>;
  };
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
          abi: deployment.abi,
          address: deployment.address,
          client,
        }) as unknown as GetContractReturnType<typeof abi>;
        return [name, contract];
      }),
    ) as typeof this.contracts;
  }
  // get nameStr() {
  //   return nameForChain(this.isL1);
  // }
  // get name() {
  //   return ansi(ansiForChain(this.isL1), this.nameStr);
  // }
  get name() {
    return nameForChain(this.isL1);
  }
  get arrow() {
    return `${this.name}->${this.rx.name}`;
  }
  async deployPermissionedRegistry(account: Account, roles = ROLES.ALL) {
    const client = createClient(this.transport, this.client.chain, account);
    const { abi, bytecode } = artifacts.PermissionedRegistry;
    const hash = await client.deployContract({
      abi,
      bytecode,
      args: [
        this.contracts.RegistryDatastore.address,
        this.contracts.SimpleRegistryMetadata.address,
        account.address,
        roles,
      ],
    });
    const receipt = await client.waitForTransactionReceipt({ hash });
    return getContract({
      abi,
      address: receipt.contractAddress!,
      client,
    });
  }
  deployDedicatedResolver(account: Account, salt?: bigint) {
    return deployVerifiableProxy({
      walletClient: createClient(this.transport, this.client.chain, account),
      factoryAddress: this.contracts.VerifiableFactory.address,
      implAddress: this.contracts.DedicatedResolverImpl.address,
      implAbi: this.contracts.DedicatedResolverImpl.abi,
      salt,
    });
  }
  deployUserRegistry(
    account: Account,
    roles: bigint,
    admin: string,
    salt?: bigint,
  ) {
    return deployVerifiableProxy({
      walletClient: createClient(this.transport, this.client.chain, account),
      factoryAddress: this.contracts.VerifiableFactory.address,
      implAddress: this.contracts.UserRegistryImpl.address,
      implAbi: this.contracts.UserRegistryImpl.abi,
      callData: encodeFunctionData({
        abi: this.contracts.UserRegistryImpl.abi,
        functionName: "initialize",
        args: [roles, admin],
      } as any) as `0x${string}`,
      salt,
    });
  }
}

export async function setupCrossChainEnvironment({
  l2ChainId = 0xeeeeee,
  l1ChainId = l2ChainId - 1,
  l1Port = 0,
  l2Port = 0,
  urgPort = 0,
  extraAccounts = 5,
  mnemonic = "test test test test test test test test test test test junk",
  saveDeployments = false,
  quiet = !saveDeployments,
  procLog = false,
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
} = {}) {
  // shutdown functions for partial initialization
  const finalizers: (() => unknown | Promise<unknown>)[] = [];
  async function shutdown() {
    await Promise.allSettled(finalizers.map((f) => f()));
  }
  let unquiet = () => { };
  if (quiet) {
    const { log, table } = console;
    console.log = () => { };
    console.table = () => { };
    unquiet = () => {
      console.log = log;
      console.table = table;
    };
  }
  try {
    console.log("Deploying ENSv2...");
    await patchArtifactsV1();

    const names = ["deployer", "owner", "bridger", "user", "user2"];
    extraAccounts += names.length;

    process.env["RUST_LOG"] = "info";
    const l1Anvil = createAnvil({
      chainId: l1ChainId,
      port: l1Port,
      accounts: extraAccounts,
      mnemonic,
    });
    const l2Anvil = createAnvil({
      chainId: l2ChainId,
      port: l2Port,
      accounts: extraAccounts,
      mnemonic,
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
      retryCount: 0,
      keepAlive: true, // these prevent error
      reconnect: false, // spam on shutdown
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

    //await setupBridgeBlacklists(l1, l2);

    await sync();
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
      shutdown,
      saveState,
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
      const receipt = await chain.client.waitForTransactionReceipt({ hash });
      return { receipt, chain };
    }
    async function saveState(): Promise<CrossChainSnapshot> {
      const fs = await Promise.all(
        [l1Client, l2Client].map(async (c) => {
          let state = await c.request({ method: "evm_snapshot" } as any);
          return async () => {
            const ok = await c.request({
              method: "evm_revert",
              params: [state],
            } as any);
            if (!ok) throw new Error("revert failed");
            // apparently the snapshots cannot be reused
            state = await c.request({ method: "evm_snapshot" } as any);
          };
        }),
      );
      return async () => {
        await Promise.all(fs.map((f) => f()));
      };
    }
    async function sync({
      blocks = 1,
      warpSec = 0,
    }: { blocks?: number; warpSec?: number } = {}) {
      const [b0, b1] = await Promise.all([
        l1Client.getBlock(),
        l2Client.getBlock(),
      ]);
      const dt = Number(b0.timestamp - b1.timestamp);
      const interval = warpSec + Math.max(0, -dt);
      await Promise.all([
        l1Client.mine({ blocks, interval }),
        l2Client.mine({ blocks, interval: warpSec + Math.max(0, +dt) }),
      ]);
      return b0.timestamp + BigInt(interval);
    }
  } catch (err) {
    await shutdown();
    throw err;
  } finally {
    unquiet();
  }
}

// async function setupBridgeBlacklists(l1: L1Deployment, l2: L2Deployment) {
//   // prevent ejection to the other sides controller
//   const blacklisted = [
//     l1.contracts.BridgeController.address,
//     l2.contracts.BridgeController.address,
//   ];
//   for (const x of blacklisted) {
//     await Promise.all([
//       l1.contracts.BridgeController.write.setInvalidTransferOwner([x, true]),
//       l2.contracts.BridgeController.write.setInvalidTransferOwner([x, true]),
//     ]);
//   }
// }

async function setupEnsDotEth(l1: L1Deployment, owner: Account) {
  // create registry for "ens.eth"
  const ens_ethRegistry = await l1.deployPermissionedRegistry(owner);
  // create "ens.eth"
  await l1.contracts.ETHRegistry.write.register([
    "ens",
    owner.address,
    ens_ethRegistry.address,
    zeroAddress,
    0n,
    MAX_EXPIRY,
  ]);
  // create "dnsname.ens.eth"
  const dnsnameResolver = await l1.deployDedicatedResolver(owner);
  await dnsnameResolver.write.setAddr([
    60n,
    l1.contracts.DNSTXTResolver.address, // set to DNSTXTResolver
  ]);
  await ens_ethRegistry.write.register([
    "dnsname",
    owner.address,
    zeroAddress,
    dnsnameResolver.address,
    0n,
    MAX_EXPIRY,
  ]);
  // create "dnsalias.ens.eth"
  const dnsaliasResolver = await l1.deployDedicatedResolver(owner);
  await dnsaliasResolver.write.setAddr([
    60n,
    l1.contracts.DNSAliasResolver.address, // set to DNSAliasResolver
  ]);
  await ens_ethRegistry.write.register([
    "dnsalias",
    owner.address,
    zeroAddress,
    dnsaliasResolver.address,
    0n,
    MAX_EXPIRY,
  ]);
}
