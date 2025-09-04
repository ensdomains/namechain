import { anvil } from "prool/instances";
import { type Environment, executeDeployScripts, resolveConfig } from "rocketh";
import {
  createWalletClient,
  getContract,
  webSocket,
  keccak256,
  stringToBytes,
  publicActions,
  testActions,
  zeroAddress,
  type Account,
  type Chain,
  type Client,
} from "viem";
import { mnemonicToAccount } from "viem/accounts";
import { artifacts } from "@rocketh";
import { rm } from "node:fs/promises";

import type { RockethL1Arguments, RockethArguments } from "./types.ts";
import { deployArtifact } from "../test/fixtures/deployArtifact.js";
import { deployVerifiableProxy } from "../test/fixtures/deployVerifiableProxy.js";
import { urgArtifact } from "../test/fixtures/externalArtifacts.js";
import { UncheckedRollup } from "../lib/unruggable-gateways/src/UncheckedRollup.js";
import { WebSocketProvider } from "ethers/providers";
import { Gateway } from "../lib/unruggable-gateways/src/gateway.js";
import { serve } from "@namestone/ezccip/serve";
import { patchArtifactsV1 } from "./patchArtifactsV1.ts";
import { MAX_EXPIRY, ROLES } from "../deploy/constants.ts";

export type CrosschainSnapshot = () => Promise<void>;

function createDeploymentGetter<C extends Client>(
  environment: Environment,
  client: C,
) {
  return <ContractName extends keyof typeof artifacts>(
    contractName: ContractName,
    deployedName: string = contractName,
  ) => {
    const deployment = environment.get(deployedName);
    return getContract({
      abi: deployment.abi as (typeof artifacts)[ContractName]["abi"],
      address: deployment.address,
      client,
    });
  };
}

function deploymentAddresses(env: Environment) {
  return Object.fromEntries(
    Object.entries(env.deployments).map(([key, { address }]) => [key, address]),
  );
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
  pollingInterval = 0,
}: {
  l1ChainId?: number;
  l2ChainId?: number;
  l1Port?: number;
  l2Port?: number;
  urgPort?: number;
  extraAccounts?: number;
  mnemonic?: string;
  saveDeployments?: boolean;
  pollingInterval?: number;
} = {}) {
  console.log("Deploying ENSv2...");

  const cacheTime = 0; // must be 0 due to client caching

  const names = ["deployer", "owner", "bridger", "user"];
  extraAccounts += names.length;

  const l1Anvil = anvil({
    chainId: l1ChainId,
    port: l1Port,
    accounts: extraAccounts,
    mnemonic,
  });
  const l2Anvil = anvil({
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

    //l1Anvil.on("message", console.log);
    //l2Anvil.on("message", console.log);

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
    const l1Client = createWalletClient({
      chain: {
        id: l1ChainId,
        name: "Mainnet (L1)",
        nativeCurrency,
        rpcUrls: { default: { http: [`http://${l1HostPort}`] } },
      },
      transport: l1Transport,
      account: deployer,
      pollingInterval,
      cacheTime,
    })
      .extend(publicActions)
      .extend(testActions({ mode: "anvil" }));
    const l2Client = createWalletClient({
      chain: {
        id: l2ChainId,
        name: "Namechain (L2)",
        nativeCurrency,
        rpcUrls: { default: { http: [`http://${l2HostPort}`] } },
      },
      transport: l2Transport,
      account: deployer,
      pollingInterval,
      cacheTime,
    })
      .extend(publicActions)
      .extend(testActions({ mode: "anvil" }));

    async function deployChain(chain: Chain, args?: RockethArguments) {
      const tag = chain.id === l1ChainId ? "l1" : "l2";
      const name = `${tag}-local`;
      if (saveDeployments) {
        await rm(new URL(`../deployments/${name}`, import.meta.url), {
          recursive: true,
          force: true,
        });
      }
      const tags = [tag, "local"];
      const scripts = [`deploy/${tag}`, "deploy/shared"];
      if (tag == "l1") {
        await patchArtifactsV1();
        process.env.BATCH_GATEWAY_URLS = '["x-batch-gateway:true"]';
        scripts.unshift("lib/ens-contracts/deploy");
        tags.push("use_root"); // deploy root contracts
        tags.push("allow_unsafe"); // tate hacks
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
            pollingInterval: Math.max(1, pollingInterval) / 1000, // can't be 0
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

    const l1Contracts = createDeploymentGetter(l1Deploy, l1Client);
    const l1 = {
      hostPort: l1HostPort,
      client: l1Client,
      transport: l1Transport,
      deployments: deploymentAddresses(l1Deploy),
      contracts: {
        // v1+v2
        batchGatewayProvider: l1Contracts(
          "GatewayProvider",
          "BatchGatewayProvider",
        ),
        dnssecGatewayProvider: l1Contracts(
          "GatewayProvider",
          "DNSSECGatewayProvider",
        ),
        // v1
        rootV1: l1Contracts("Root"),
        ensRegistryV1: l1Contracts("ENSRegistry"),
        ethRegistrarV1: l1Contracts("BaseRegistrarImplementation"),
        reverseRegistrarV1: l1Contracts("ReverseRegistrar"),
        publicResolverV1: l1Contracts("PublicResolver"),
        nameWrapperV1: l1Contracts("NameWrapper"),
        // v1 compat
        defaultReverseRegistrar: l1Contracts("DefaultReverseRegistrar"),
        defaultReverseResolver: l1Contracts("DefaultReverseResolver"),
        //universalResolverV1: l1Contracts("UniversalResolver"), ==> no deploy script yet
        // v2
        ejectionController: l1Contracts("L1EjectionController"),
        ethRegistry: l1Contracts("PermissionedRegistry", "ETHRegistry"),
        ethSelfResolver: l1Contracts("DedicatedResolver", "ETHSelfResolver"),
        ethReverseResolver: l1Contracts("ETHReverseResolver"),
        ethReverseRegistrar: l1Contracts(
          "L2ReverseRegistrar",
          "ETHReverseRegistrar",
        ),
        ethTLDResolver: l1Contracts("ETHTLDResolver"),
        dnsTLDResolver: l1Contracts("DNSTLDResolver"),
        dnsTXTResolver: l1Contracts("DNSTXTResolver"),
        dnsAliasResolver: l1Contracts("DNSAliasResolver"),
        mockBridge: l1Contracts("MockL1Bridge"),
        rootRegistry: l1Contracts("PermissionedRegistry", "RootRegistry"),
        universalResolver: l1Contracts("UniversalResolverV2"),
        // shared
        registryDatastore: l1Contracts("RegistryDatastore"),
        simpleRegistryMetadata: l1Contracts("SimpleRegistryMetadata"),
        dedicatedResolverFactory: l1Contracts(
          "VerifiableFactory",
          "DedicatedResolverFactory",
        ),
        dedicatedResolverImpl: l1Contracts(
          "DedicatedResolver",
          "DedicatedResolverImpl",
        ),
      },
      createClient,
      deployDedicatedResolver,
      deployPermissionedRegistry,
    };

    const l2Contracts = createDeploymentGetter(l2Deploy, l2Client);
    const l2 = {
      hostPort: l2HostPort,
      client: l2Client,
      transport: l2Transport,
      deployments: deploymentAddresses(l2Deploy),
      contracts: {
        // v2
        ethRegistrar: l2Contracts("ETHRegistrar"),
        ethRegistry: l2Contracts("PermissionedRegistry", "ETHRegistry"),
        bridgeController: l2Contracts("L2BridgeController"),
        mockBridge: l2Contracts("MockL2Bridge"),
        priceOracle: l2Contracts("IPriceOracle", "PriceOracle"),
        // shared
        registryDatastore: l2Contracts("RegistryDatastore"),
        simpleRegistryMetadata: l2Contracts("SimpleRegistryMetadata"),
        dedicatedResolverFactory: l2Contracts(
          "VerifiableFactory",
          "DedicatedResolverFactory",
        ),
        dedicatedResolverImpl: l2Contracts(
          "DedicatedResolver",
          "DedicatedResolverImpl",
        ),
      },
      createClient,
      deployDedicatedResolver,
      deployPermissionedRegistry,
    };

    await setup_ens_eth(deployer);
    console.log("Setup ens.eth");

    await sync();
    let resetState = await saveState();

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
      resetState,
      saveState,
      sync,
      shutdown,
    };
    async function saveState(): Promise<CrosschainSnapshot> {
      const [s1, s2] = await Promise.all([
        l1Client.dumpState(),
        l2Client.dumpState(),
      ]);
      // const [s1, s2] = await Promise.all([
      //   l1Client.request({ method: "evm_snapshot", params: [] } as any),
      //   l2Client.request({ method: "evm_snapshot", params: [] } as any),
      // ]);
      return async () => {
        const reset = { method: "anvil_reset", params: [] } as any;
        await Promise.all([
          l1Client.request(reset).then(() => l1Client.loadState({ state: s1 })),
          l2Client.request(reset).then(() => l2Client.loadState({ state: s2 })),
        ]);
        // await Promise.all([
        //   l1Client.request({ method: "evm_revert", params: [s1] } as any),
        //   l2Client.request({ method: "evm_revert", params: [s2] } as any),
        // ]);
      };
    }
    async function sync() {
      const args = { blocks: 1 };
      await Promise.all([l1Client.mine(args), l2Client.mine(args)]);
    }
    function createClient(this: typeof l1 | typeof l2, account: Account) {
      return createWalletClient({
        chain: this.client.chain,
        transport: this.transport,
        account,
        pollingInterval,
        cacheTime,
      });
    }
    async function deployDedicatedResolver(
      this: typeof l1 | typeof l2,
      account: Account,
      salt = BigInt(keccak256(stringToBytes(new Date().toISOString()))),
    ) {
      return deployVerifiableProxy({
        walletClient: this.createClient(account),
        factoryAddress: this.contracts.dedicatedResolverFactory.address,
        implAddress: this.contracts.dedicatedResolverImpl.address,
        implAbi: this.contracts.dedicatedResolverImpl.abi,
        salt,
      });
    }
    async function deployPermissionedRegistry(
      this: typeof l1 | typeof l2,
      account: Account,
      roles = ROLES.ALL,
    ) {
      const client = this.createClient(account);
      const abi = artifacts.PermissionedRegistry.abi;
      const hash = await client.deployContract({
        abi,
        bytecode: artifacts.PermissionedRegistry.bytecode,
        args: [
          this.contracts.registryDatastore.address,
          this.contracts.simpleRegistryMetadata.address,
          account.address,
          roles,
        ],
      });
      const receipt = await this.client.waitForTransactionReceipt({
        hash,
      });
      return getContract({
        abi,
        address: receipt.contractAddress!,
        client,
      });
    }
    async function setup_ens_eth(owner: Account) {
      // create registry for "ens.eth"
      const ens_ethRegistry = await l1.deployPermissionedRegistry(owner);
      // create "ens.eth"
      await l1.contracts.ethRegistry.write.register([
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
        l1.contracts.dnsTXTResolver.address, // set to DNSTXTResolver
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
        l1.contracts.dnsAliasResolver.address, // set to DNSAliasResolver
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
  } catch (err) {
    await shutdown();
    throw err;
  }
}

export type CrossChainEnvironment = Awaited<
  ReturnType<typeof setupCrossChainEnvironment>
>;
export type L1Contracts = CrossChainEnvironment["l1"]["contracts"];
export type L2Contracts = CrossChainEnvironment["l2"]["contracts"];
export type L1Client = CrossChainEnvironment["l1"]["client"];
export type L2Client = CrossChainEnvironment["l2"]["client"];
