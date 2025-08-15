import { anvil } from "prool/instances";
import { executeDeployScripts, resolveConfig, type Environment } from "rocketh";
import {
  createWalletClient,
  encodeFunctionData,
  getContract,
  parseEventLogs,
  webSocket,
  keccak256,
  stringToBytes,
  publicActions,
  type Client,
  type GetContractReturnType,
} from "viem";
import { waitForTransactionReceipt } from "viem/actions";
import { mnemonicToAccount } from "viem/accounts";

import { artifacts } from "@rocketh";
import { deployArtifact } from "../test/fixtures/deployArtifact.js";
import { urgArtifact } from "../test/fixtures/externalArtifacts.js";
import { UncheckedRollup } from "../lib/unruggable-gateways/src/UncheckedRollup.js";
import { WebSocketProvider } from "ethers/providers";
import { Gateway } from "../lib/unruggable-gateways/src/gateway.js";
import { serve } from "@namestone/ezccip/serve";

function createDeploymentGetter<C extends Client>(
  environment: Environment,
  client: C,
) {
  return <ContractName extends keyof typeof artifacts>(
    name: ContractName | string,
  ) => {
    const deployment = environment.get(name);
    return getContract({
      abi: deployment.abi,
      address: deployment.address,
      client,
    }) as unknown as GetContractReturnType<
      (typeof artifacts)[ContractName]["abi"],
      C
    >;
  };
}

export async function setupCrossChainEnvironment({
  l1ChainId = 0xeeeeee,
  l2ChainId = l1ChainId + 1,
  l1Port = 0,
  l2Port = 0,
  urgPort = 0,
  numAccounts = 5,
  mnemonic = "test test test test test test test test test test test junk",
}: {
  l1ChainId?: number;
  l2ChainId?: number;
  l1Port?: number;
  l2Port?: number;
  urgPort?: number;
  numAccounts?: number;
  mnemonic?: string;
} = {}) {
  console.log("Setting up cross-chain ENS v2 environment...");

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
      name: "",
    }),
  );

  // name accounts (exposed as `namedAccounts` in rocketh)
  const deployer = accounts[0];
  deployer.name = "deployer";
  accounts[1].name = "owner";

  // shutdown functions for partial initialization
  const finalizers: (() => Promise<void>)[] = [];
  async function shutdown() {
    await Promise.allSettled(finalizers.map((f) => f()));
  }

  // parse `host:port` from the anvil boot message
  function parseHost(lines: string[]) {
    const match = lines
      .join("\n")
      .trim()
      .match(/Listening on (.*)$/);
    if (!match) throw new Error(`expected host`);
    return match[1];
  }

  try {
    await l1Anvil.start();
    finalizers.push(() => l1Anvil.stop());

    await l2Anvil.start();
    finalizers.push(() => l2Anvil.stop());

    const l1HostPort = parseHost(l1Anvil.messages.get());
    const l2HostPort = parseHost(l2Anvil.messages.get());

    const transportOptions = {
      retryCount: 0,
      keepAlive: true, // these prevent error
      reconnect: false, // spam on shutdown
    } as const;
    const l1Transport = webSocket(`ws://${l1HostPort}`, transportOptions);
    const l2Transport = webSocket(`ws://${l2HostPort}`, transportOptions);

    const l1ChainInfo = {
      id: l1ChainId,
      name: "L1 Local",
      nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
      rpcUrls: {
        default: { http: [`http://${l1HostPort}`] },
      },
    };

    const l2ChainInfo = {
      id: l2ChainId,
      name: "L2 Local",
      nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
      rpcUrls: {
        default: { http: [`http://${l2HostPort}`] },
      },
    };

    const l1Client = createWalletClient({
      chain: l1ChainInfo,
      transport: l1Transport,
      account: deployer,
    }).extend(publicActions);
    const l2Client = createWalletClient({
      chain: l2ChainInfo,
      transport: l2Transport,
      account: deployer,
    }).extend(publicActions);

    console.log("Deploying L2 Contracts...");
    const l2Deploy = await executeDeployScripts(
      resolveConfig({
        network: {
          nodeUrl: `http://${l2HostPort}`,
          name: "l2-local",
          tags: ["l2", "local"],
          fork: false,
          scripts: ["deploy/l2", "deploy/shared"],
          publicInfo: l2ChainInfo, // squelches error
        },
        askBeforeProceeding: false,
        accounts: Object.fromEntries(
          accounts.filter((x) => x.name).map((x) => [x.name, x.address]),
        ),
      }),
    );

    console.log("Deploying Urg..");
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

    console.log("Deploying L1 Contracts...");
    const l1Deploy = await executeDeployScripts(
      resolveConfig({
        network: {
          nodeUrl: `http://${l1HostPort}`,
          name: "l1-local",
          tags: ["l1", "local"],
          fork: false,
          scripts: ["deploy/l1", "deploy/shared"],
          publicInfo: l1ChainInfo,
        },
        askBeforeProceeding: false,
        accounts: Object.fromEntries(
          accounts.filter((x) => x.name).map((x) => [x.name, x.address]),
        ),
      }),
      {
        l2Deploy,
        verifierAddress,
      },
    );

    console.log("Cross-chain environment setup complete!");

    const l1Contracts = createDeploymentGetter(l1Deploy, l1Client);
    const l1 = {
      hostPort: l1HostPort,
      client: l1Client,
      transport: l1Transport,
      anvil: l1Anvil,
      contracts: {
        // v1+v2
        batchGatewayProvider: l1Contracts<"GatewayProvider">(
          "BatchGatewayProvider",
        ),
        // v1
        ensRegistryV1: l1Contracts<"ENSRegistry">("ENSRegistryV1"),
        ethRegistrarV1:
          l1Contracts<"BaseRegistrarImplementation">("ETHRegistrarV1"),
        reverseRegistrarV1:
          l1Contracts<"ReverseRegistrar">("ReverseRegistrarV1"),
        publicResolverV1: l1Contracts<"PublicResolver">("PublicResolverV1"),
        universalResolverV1: l1Contracts<"UniversalResolver">(
          "UniversalResolverV1",
        ),
        // v2
        ejectionController: l1Contracts("L1EjectionController"),
        ethRegistry: l1Contracts("L1ETHRegistry"),
        ethSelfResolver: l1Contracts<"DedicatedResolver">("ETHSelfResolver"),
        ethTLDResolver: l1Contracts("ETHTLDResolver"),
        //dnsTLDResolver: l1Contracts("DNSTLDResolver"),
        mockBridge: l1Contracts("MockL1Bridge"),
        rootRegistry: l1Contracts<"PermissionedRegistry">("RootRegistry"),
        universalResolver:
          l1Contracts<"UniversalResolverV2">("UniversalResolver"),
        // shared
        registryDatastore: l1Contracts("RegistryDatastore"),
        simpleRegistryMetadata: l1Contracts("SimpleRegistryMetadata"),
        dedicatedResolverFactory: l1Contracts<"VerifiableFactory">(
          "DedicatedResolverFactory",
        ),
        dedicatedResolverImpl: l1Contracts<"DedicatedResolver">(
          "DedicatedResolverImpl",
        ),
      },
      deployDedicatedResolver,
    };

    const l2Contracts = createDeploymentGetter(l2Deploy, l2Client);
    const l2 = {
      hostPort: l2HostPort,
      client: l2Client,
      transport: l2Transport,
      anvil: l2Anvil,
      contracts: {
        // v2
        ethRegistrar: l2Contracts("ETHRegistrar"),
        ethRegistry: l2Contracts<"PermissionedRegistry">("ETHRegistry"),
        bridgeController: l2Contracts("L2BridgeController"),
        mockBridge: l2Contracts("MockL2Bridge"),
        priceOracle: l2Contracts<"IPriceOracle">("PriceOracle"),
        // shared
        registryDatastore: l2Contracts("RegistryDatastore"),
        simpleRegistryMetadata: l2Contracts("SimpleRegistryMetadata"),
        dedicatedResolverFactory: l2Contracts<"VerifiableFactory">(
          "DedicatedResolverFactory",
        ),
        dedicatedResolverImpl: l2Contracts<"DedicatedResolver">(
          "DedicatedResolverImpl",
        ),
      },
      deployDedicatedResolver,
    };
    return {
      accounts,
      namedAccounts: Object.fromEntries(
        accounts.filter((x) => x.name).map((x) => [x.name, x]),
      ),
      l1,
      l2,
      urg: {
        gateway,
        gatewayURL: ccip.endpoint,
        verifierAddress,
      },
      shutdown,
    };
    async function deployDedicatedResolver(
      this: typeof l1 | typeof l2,
      account = this.client.account,
      salt = BigInt(keccak256(stringToBytes(new Date().toISOString()))),
    ) {
      const client = createWalletClient({
        chain: this.client.chain,
        transport: this.transport,
        account,
      });
      const hash = await client.writeContract({
        address: this.contracts.dedicatedResolverFactory.address,
        abi: this.contracts.dedicatedResolverFactory.abi,
        functionName: "deployProxy",
        args: [
          this.contracts.dedicatedResolverImpl.address,
          salt,
          encodeFunctionData({
            abi: this.contracts.dedicatedResolverImpl.abi,
            functionName: "initialize",
            args: [account.address],
          }),
        ],
      });
      const receipt = await waitForTransactionReceipt(client, { hash });
      const [log] = parseEventLogs({
        abi: this.contracts.dedicatedResolverFactory.abi,
        eventName: "ProxyDeployed",
        logs: receipt.logs,
      });
      return getContract({
        abi: artifacts.DedicatedResolver.abi,
        address: log.args.proxyAddress,
        client,
      });
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
