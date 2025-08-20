import { anvil } from "prool/instances";
import { executeDeployScripts, resolveConfig, type Environment } from "rocketh";
import {
  createWalletClient,
  getContract,
  webSocket,
  publicActions,
  testActions,
  type Account,
  type Address,
  type Chain,
  type Transport,
  Client,
  Abi,
  type GetContractReturnType,
} from "viem";
import { mnemonicToAccount } from "viem/accounts";
import { type Arguments, artifacts } from "@rocketh";
import { rm } from "node:fs/promises";

import { deployArtifact } from "../test/fixtures/deployArtifact.js";
import { deployVerifiableProxy } from "../test/fixtures/deployVerifiableProxy.ts";
import { urgArtifact } from "../test/fixtures/externalArtifacts.js";
import { UncheckedRollup } from "../lib/unruggable-gateways/src/UncheckedRollup.js";
import { WebSocketProvider } from "ethers/providers";
import { Gateway } from "../lib/unruggable-gateways/src/gateway.js";
import { serve } from "@namestone/ezccip/serve";

type DeployedArtifacts = Record<string, Abi>;

const sharedContracts = {
  RegistryDatastore: artifacts.RegistryDatastore.abi,
  SimpleRegistryMetadata: artifacts.SimpleRegistryMetadata.abi,
  DedicatedResolverFactory: artifacts.VerifiableFactory.abi,
  DedicatedResolverImpl: artifacts.DedicatedResolver.abi,
} as const satisfies DeployedArtifacts;

const l1Contracts = {
  ...sharedContracts,
  // v1
  BatchGatewayProvider: artifacts.GatewayProvider.abi,
  ENSRegistryV1: artifacts.ENSRegistry.abi,
  ETHRegistrarV1: artifacts.BaseRegistrarImplementation.abi,
  ReverseRegistrarV1: artifacts.ReverseRegistrar.abi,
  PublicResolverV1: artifacts.PublicResolver.abi,
  UniversalResolverV1: artifacts.UniversalResolver.abi,
  // v2
  MockL1Bridge: artifacts.MockL1Bridge.abi,
  L1EjectionController: artifacts.L1EjectionController.abi,
  ETHRegistry: artifacts.PermissionedRegistry.abi,
  ETHSelfResolver: artifacts.DedicatedResolver.abi,
  ETHTLDResolver: artifacts.ETHTLDResolver.abi,
  //DNSTLDResolver: artifacts.DNSTLDResolver.abi,
  RootRegistry: artifacts.PermissionedRegistry.abi,
  UniversalResolver: artifacts.UniversalResolverV2.abi,
} as const satisfies DeployedArtifacts;

const l2Contracts = {
  ...sharedContracts,
  MockL2Bridge: artifacts.MockL2Bridge.abi,
  L2BridgeController: artifacts.L2BridgeController.abi,
  ETHRegistrar: artifacts.ETHRegistrar.abi,
  ETHRegistry: artifacts.PermissionedRegistry.abi,
  StableTokenPriceOracle: artifacts.StableTokenPriceOracle.abi,
} as const satisfies DeployedArtifacts;

export class ChainDeployment<
  A extends typeof sharedContracts & DeployedArtifacts = typeof sharedContracts,
  C extends Client<Transport, Chain, Account> = Client<
    Transport,
    Chain,
    Account
  >,
> {
  readonly contracts: { [K in keyof A]: GetContractReturnType<A[K], C> };
  constructor(
    readonly client: C,
    readonly hostPort: string,
    readonly transport: Transport,
    readonly env: Environment,
    namedArtifacts: A,
  ) {
    this.contracts = Object.fromEntries(
      Object.entries(namedArtifacts).map(([name, abi]) => {
        const deployment = env.get(name);
        const contract = getContract({
          abi: deployment.abi,
          address: deployment.address,
          client,
        }) as unknown as GetContractReturnType<typeof abi, C>;
        return [name, contract];
      }),
    ) as typeof this.contracts;
  }
  deployDedicatedResolver(account: Account, salt?: bigint) {
    return deployVerifiableProxy({
      walletClient: createWalletClient({
        chain: this.client.chain,
        transport: this.transport,
        account,
      }),
      factoryAddress: this.contracts.DedicatedResolverFactory.address,
      implAddress: this.contracts.DedicatedResolverImpl.address,
      implAbi: this.contracts.DedicatedResolverImpl.abi,
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
  numAccounts = 5,
  mnemonic = "test test test test test test test test test test test junk",
  saveDeployments = false,
}: {
  l1ChainId?: number;
  l2ChainId?: number;
  l1Port?: number;
  l2Port?: number;
  urgPort?: number;
  numAccounts?: number;
  mnemonic?: string;
  saveDeployments?: boolean;
} = {}) {
  console.log("Deploying ENSv2...");

  const l1Anvil = anvil({
    chainId: l1ChainId,
    port: l1Port,
    accounts: numAccounts,
    mnemonic,
  });
  const l2Anvil = anvil({
    chainId: l2ChainId,
    port: l2Port,
    accounts: numAccounts,
    mnemonic,
  });

  // use same accounts on both chains
  const accounts = Array.from({ length: numAccounts }, (_, i) =>
    Object.assign(mnemonicToAccount(mnemonic, { addressIndex: i }), {
      name: `unnamed${i}`, // default name
    }),
  );

  // name accounts (exposed as `namedAccounts` in rocketh)
  const deployer = accounts[0];
  deployer.name = "deployer";
  accounts[1].name = "bridge";
  accounts[2].name = "owner";

  // shutdown functions for partial initialization
  const finalizers: (() => Promise<void>)[] = [];
  async function shutdown() {
    await Promise.allSettled(finalizers.map((f) => f()));
  }

  try {
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

    const transportOptions = {
      retryCount: 0,
      keepAlive: true, // these prevent error
      reconnect: false, // spam on shutdown
    } as const;
    const l1Transport = webSocket(`ws://${l1HostPort}`, transportOptions);
    const l2Transport = webSocket(`ws://${l2HostPort}`, transportOptions);

    const nativeCurrency = { name: "Ether", symbol: "ETH", decimals: 18 };
    const pollingInterval = 25;

    const l1Client = createWalletClient({
      chain: {
        id: l1ChainId,
        name: "L1 Local",
        nativeCurrency,
        rpcUrls: { default: { http: [`http://${l1HostPort}`] } },
      },
      transport: l1Transport,
      account: deployer,
      pollingInterval,
    })
      .extend(publicActions)
      .extend(testActions({ mode: "anvil" }));

    const l2Client = createWalletClient({
      chain: {
        id: l2ChainId,
        name: "L2 Local",
        nativeCurrency,
        rpcUrls: { default: { http: [`http://${l2HostPort}`] } },
      },
      transport: l2Transport,
      account: deployer,
      pollingInterval,
    })
      .extend(publicActions)
      .extend(testActions({ mode: "anvil" }));

    async function deployRocketh(tag: string, chain: Chain, args?: Arguments) {
      const name = `${tag}-local`;
      if (saveDeployments) {
        await rm(new URL(`../deployments/${name}`, import.meta.url), {
          recursive: true,
          force: true,
        });
      }
      return executeDeployScripts(
        resolveConfig({
          network: {
            nodeUrl: chain.rpcUrls.default.http[0],
            name,
            tags: [tag, "local"],
            fork: false,
            scripts: [`deploy/${tag}`, "deploy/shared"],
            publicInfo: {
              name,
              nativeCurrency: chain.nativeCurrency,
              rpcUrls: { default: { http: [...chain.rpcUrls.default.http] } },
            },
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
    const l2Deploy = await deployRocketh("l2", l2Client.chain);

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
    const l1Deploy = await deployRocketh("l1", l1Client.chain, {
      l2Deploy,
      verifierAddress,
    });

    console.log("Deployed ENSv2");

    const l1 = new ChainDeployment(
      l1Client,
      l1HostPort,
      l1Transport,
      l1Deploy,
      l1Contracts,
    );

    const l2 = new ChainDeployment(
      l2Client,
      l2HostPort,
      l2Transport,
      l2Deploy,
      l2Contracts,
    );

    return {
      accounts,
      namedAccounts: Object.fromEntries(accounts.map((x) => [x.name, x])),
      l1,
      l2,
      urg: {
        gateway,
        gatewayURL: ccip.endpoint,
        verifierAddress,
      },
      sync,
      shutdown,
    } as const;
    async function sync() {
      //await Promise.all([l1, l2].map((x) => x.client.mine({ blocks: 1 })));
      const args = { blocks: 1 };
      await Promise.all([l1Client.mine(args), l2Client.mine(args)]);
    }
  } catch (err) {
    await shutdown();
    throw err;
  }
}

export type CrossChainEnvironment = Awaited<
  ReturnType<typeof setupCrossChainEnvironment>
>;
