import { createPublicClient, http, type Chain, type PublicClient } from "viem";
import { readFileSync } from "fs";
import { join } from "path";

// Define chain types
export const l1Chain: Chain = {
  id: 31337,
  name: "Local L1",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: ["http://127.0.0.1:8545"] },
    public: { http: ["http://127.0.0.1:8545"] },
  },
};

export const l2Chain: Chain = {
  id: 31338,
  name: "Local L2",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: ["http://127.0.0.1:8546"] },
    public: { http: ["http://127.0.0.1:8546"] },
  },
};

export const otherl2Chain: Chain = {
  id: 31339,
  name: "Other L2",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: ["http://127.0.0.1:8547"] },
    public: { http: ["http://127.0.0.1:8547"] },
  },
};

// Connect to the networks
export const l1Client = createPublicClient({
  chain: l1Chain,
  transport: http(),
});

export const l2Client = createPublicClient({
  chain: l2Chain,
  transport: http(),
});

export const otherl2Client = createPublicClient({
  chain: otherl2Chain,
  transport: http(),
});

// Deployment file paths
export const deploymentPaths = {
  rootRegistry: join(process.cwd(), "deployments", "l1-local", "RootRegistry.json"),
  l1EthRegistry: join(process.cwd(), "deployments", "l1-local", "L1ETHRegistry.json"),
  ethRegistry: join(process.cwd(), "deployments", "l2-local", "ETHRegistry.json"),
  l1RegistryDatastore: join(process.cwd(), "deployments", "l1-local", "RegistryDatastore.json"),
  l2RegistryDatastore: join(process.cwd(), "deployments", "l2-local", "RegistryDatastore.json"),
  dedicatedResolverImpl: join(process.cwd(), "deployments", "l2-local", "DedicatedResolverImpl.json"),
  l1EjectionController: join(process.cwd(), "deployments", "l1-local", "L1EjectionController.json"),
  l2EjectionController: join(process.cwd(), "deployments", "l2-local", "L2EjectionController.json"),
  mockDurinL2Registry: join(process.cwd(), "deployments", "otherl2-local", "MockDurinL2Registry.json"),
  mockDurinL1ResolverImpl: join(process.cwd(), "deployments", "l1-local", "MockDurinL1ResolverImpl.json"),
  userRegistryImpl: join(process.cwd(), "deployments", "l2-local", "UserRegistryImpl.json"),
  l1VerifiableFactory: join(process.cwd(), "deployments", "l1-local", "VerifiableFactory.json"),
  l2VerifiableFactory: join(process.cwd(), "deployments", "l2-local", "VerifiableFactory.json"),
  l1DedicatedResolverImpl: join(process.cwd(), "deployments", "l1-local", "DedicatedResolverImpl.json"),
  l2DedicatedResolverImpl: join(process.cwd(), "deployments", "l2-local", "DedicatedResolverImpl.json"),
  registryDatastore: join(process.cwd(), "deployments", "l2-local", "RegistryDatastore.json"),
  registryMetadata: join(process.cwd(), "deployments", "l2-local", "SimpleRegistryMetadata.json"),
} as const;

// Load deployment files
export function loadDeployment(path: string) {
  return JSON.parse(readFileSync(path, "utf8"));
}

// Load all deployments
export const deployments = {
  rootRegistry: loadDeployment(deploymentPaths.rootRegistry),
  l1EthRegistry: loadDeployment(deploymentPaths.l1EthRegistry),
  ethRegistry: loadDeployment(deploymentPaths.ethRegistry),
  l1RegistryDatastore: loadDeployment(deploymentPaths.l1RegistryDatastore),
  l2RegistryDatastore: loadDeployment(deploymentPaths.l2RegistryDatastore),
  dedicatedResolverImpl: loadDeployment(deploymentPaths.dedicatedResolverImpl),
  l1EjectionController: loadDeployment(deploymentPaths.l1EjectionController),
  l2EjectionController: loadDeployment(deploymentPaths.l2EjectionController),
  mockDurinL2Registry: loadDeployment(deploymentPaths.mockDurinL2Registry),
  mockDurinL1ResolverImpl: loadDeployment(deploymentPaths.mockDurinL1ResolverImpl),
  userRegistryImpl: loadDeployment(deploymentPaths.userRegistryImpl),
  l1VerifiableFactory: loadDeployment(deploymentPaths.l1VerifiableFactory),
  l2VerifiableFactory: loadDeployment(deploymentPaths.l2VerifiableFactory),
  l1DedicatedResolverImpl: loadDeployment(deploymentPaths.l1DedicatedResolverImpl),
  l2DedicatedResolverImpl: loadDeployment(deploymentPaths.l2DedicatedResolverImpl),
  registryDatastore: loadDeployment(deploymentPaths.registryDatastore),
  registryMetadata: loadDeployment(deploymentPaths.registryMetadata),
} as const;

// Extract ABIs for events
export const eventABIs = {
  registryEvents: deployments.l1EthRegistry.abi.filter((item: any) => item.type === "event"),
  datastoreEvents: deployments.l1RegistryDatastore.abi.filter((item: any) => item.type === "event"),
  dedicatedResolverEvents: deployments.dedicatedResolverImpl.abi.filter((item: any) => item.type === "event"),
  ejectionControllerEvents: deployments.l1EjectionController.abi.filter((item: any) => item.type === "event"),
  mockDurinL2RegistryEvents: deployments.mockDurinL2Registry.abi.filter((item: any) => item.type === "event"),
  mockDurinL1ResolverEvents: deployments.mockDurinL1ResolverImpl.abi.filter((item: any) => item.type === "event"),
  userRegistryEvents: deployments.userRegistryImpl.abi.filter((item: any) => item.type === "event"),
} as const;

export const resolverEvents = [...eventABIs.dedicatedResolverEvents, ...eventABIs.mockDurinL1ResolverEvents]; 