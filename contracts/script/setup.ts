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
  type Client,
  type GetContractReturnType,
} from "viem";
import { waitForTransactionReceipt } from "viem/actions";
import { mnemonicToAccount } from "viem/accounts";

import { artifacts } from "@rocketh";
import { readConfig } from "./readConfig.js";
import { deployArtifact } from "../test/fixtures/deployArtifact.js";
import { urgArtifact } from "../test/fixtures/externalArtifacts.js";
import { UncheckedRollup } from "../lib/unruggable-gateways/src/UncheckedRollup.js";
import { WebSocketProvider } from "ethers/providers";
import { Gateway } from "../lib/unruggable-gateways/src/gateway.js";
import { serve } from "@namestone/ezccip/serve";

const l1Config = {
  port: 8545,
  chainId: 31337,
};

const l2Config = {
  port: 8546,
  chainId: 31338,
};

const urgConfig = {
  port: 8000,
};

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

export async function setupCrossChainEnvironment({ numAccounts = 5 } = {}) {
  console.log("Setting up cross-chain ENS v2 environment...");

  const mnemonic =
    "test test test test test test test test test test test junk";

  const l1Anvil = anvil({ ...l1Config, accounts: numAccounts, mnemonic });
  const l2Anvil = anvil({ ...l2Config, accounts: numAccounts, mnemonic });

  const l1HostPort = `${l1Anvil.host}:${l1Anvil.port}`;
  const l2HostPort = `${l2Anvil.host}:${l2Anvil.port}`;

  const finalizers: (() => Promise<void>)[] = [];
  async function shutdown() {
    await Promise.allSettled(finalizers.map((f) => f()));
  }

  try {
    await l1Anvil.start();
    finalizers.push(() => l1Anvil.stop());

    await l2Anvil.start();
    finalizers.push(() => l2Anvil.stop());

    const accounts = Array.from({ length: numAccounts }, (_, i) =>
      mnemonicToAccount(mnemonic, { addressIndex: i }),
    );

    const deployer = accounts[0];

    const l1Chain = {
      id: l1Config.chainId,
      name: "L1 Local",
      nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
      rpcUrls: {
        default: { http: [`http://${l1HostPort}`] },
        public: { http: [`http://${l1HostPort}`] },
      },
    } as const;

    const l2Chain = {
      id: l2Config.chainId,
      name: "L2 Local",
      nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
      rpcUrls: {
        default: { http: [`http://${l2HostPort}`] },
        public: { http: [`http://${l2HostPort}`] },
      },
    } as const;

    const l1Transport = webSocket(`ws://${l1HostPort}`, { retryCount: 0 });
    const l2Transport = webSocket(`ws://${l2HostPort}`, { retryCount: 0 });

    const l1Client = createWalletClient({
      chain: l1Chain,
      transport: l1Transport,
      account: deployer,
    });
    const l2Client = createWalletClient({
      chain: l2Chain,
      transport: l2Transport,
      account: deployer,
    });

    console.log("Deploying L2 Contracts...");
    const l2Deploy = await executeDeployScripts(
      resolveConfig(
        await readConfig({
          askBeforeProceeding: false,
          network: "l2-local",
        }),
      ),
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
    gateway.disableCache();
    const ccip = await serve(gateway, {
      protocol: "raw",
      port: urgConfig.port,
    });

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

    console.log("Deploying L2 Contracts...");
    const l1Deploy = await executeDeployScripts(
      resolveConfig(
        await readConfig({
          askBeforeProceeding: false,
          network: "l1-local",
        }),
      ),
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
        ejectionController: l1Contracts("L1EjectionController"),
        ethRegistry: l1Contracts("L1ETHRegistry"),
        ethTLDResolver: l1Contracts("ETHTLDResolver"),
        //dnsTLDResolver: l1Contracts("DNSTLDResolver"),
        mockBridge: l1Contracts("MockL1Bridge"),
        registryDatastore: l1Contracts("RegistryDatastore"),
        rootRegistry: l1Contracts<"PermissionedRegistry">("RootRegistry"),
        simpleRegistryMetadata: l1Contracts("SimpleRegistryMetadata"),
        universalResolver:
          l1Contracts<"UniversalResolverV2">("UniversalResolver"),
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
        ethRegistrar: l2Contracts("ETHRegistrar"),
        ethRegistry: l2Contracts<"PermissionedRegistry">("ETHRegistry"),
        bridgeController: l2Contracts("L2BridgeController"),
        mockBridge: l2Contracts("MockL2Bridge"),
        priceOracle: l2Contracts<"IPriceOracle">("PriceOracle"),
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
