// SPDX-License-Identifier: MIT
import { ethers } from "hardhat";
import { VerifiableFactory__factory } from "../typechain-types";
import { dnsEncodeName } from "./utils/dns";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // Deploy the datastore
  const RegistryDatastore = await ethers.getContractFactory("RegistryDatastore");
  const datastore = await RegistryDatastore.deploy();
  await datastore.deployed();
  console.log("RegistryDatastore deployed to:", datastore.address);

  // Deploy the metadata provider
  const SimpleRegistryMetadata = await ethers.getContractFactory("SimpleRegistryMetadata");
  const metadata = await SimpleRegistryMetadata.deploy();
  await metadata.deployed();
  console.log("SimpleRegistryMetadata deployed to:", metadata.address);

  // Deploy the registries
  const PermissionedRegistryV2 = await ethers.getContractFactory("PermissionedRegistryV2");
  
  // Define roles
  const ROLE_ADMIN = 1n << 0n;
  const ROLE_REGISTRAR = 1n << 1n;
  const ROLE_SET_RESOLVER = 1n << 2n;
  const ROLE_SET_SUBREGISTRY = 1n << 3n;
  const ROLE_SET_TOKEN_OBSERVER = 1n << 4n;
  const ROLE_RENEW = 1n << 5n;
  
  const deployerRoles = ROLE_ADMIN | ROLE_REGISTRAR | ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY | ROLE_SET_TOKEN_OBSERVER | ROLE_RENEW;
  
  // Deploy root registry
  const rootRegistry = await PermissionedRegistryV2.deploy(datastore.address, metadata.address, deployerRoles);
  await rootRegistry.deployed();
  console.log("RootRegistry deployed to:", rootRegistry.address);
  
  // Deploy ETH registry
  const ethRegistry = await PermissionedRegistryV2.deploy(datastore.address, metadata.address, deployerRoles);
  await ethRegistry.deployed();
  console.log("ETHRegistry deployed to:", ethRegistry.address);
  
  // Deploy example registry
  const exampleRegistry = await PermissionedRegistryV2.deploy(datastore.address, metadata.address, deployerRoles);
  await exampleRegistry.deployed();
  console.log("ExampleRegistry deployed to:", exampleRegistry.address);
  
  // Deploy XYZ registry (for aliasing demo)
  const xyzRegistry = await PermissionedRegistryV2.deploy(datastore.address, metadata.address, deployerRoles);
  await xyzRegistry.deployed();
  console.log("XYZRegistry deployed to:", xyzRegistry.address);

  // Deploy the resolver implementation
  const SingleNameResolver = await ethers.getContractFactory("SingleNameResolver");
  const resolverImplementation = await SingleNameResolver.deploy();
  await resolverImplementation.deployed();
  console.log("SingleNameResolver implementation deployed to:", resolverImplementation.address);

  // Deploy the factory
  const VerifiableFactory = await ethers.getContractFactory("VerifiableFactory");
  const factory = await VerifiableFactory.deploy();
  await factory.deployed();
  console.log("VerifiableFactory deployed to:", factory.address);

  // Set the resolver factory for all registries
  await rootRegistry.setResolverFactory(factory.address, resolverImplementation.address);
  await ethRegistry.setResolverFactory(factory.address, resolverImplementation.address);
  await exampleRegistry.setResolverFactory(factory.address, resolverImplementation.address);
  await xyzRegistry.setResolverFactory(factory.address, resolverImplementation.address);
  console.log("Resolver factory set for all registries");

  // Set up the registry hierarchy
  const maxExpiry = ethers.constants.MaxUint64;
  
  // Register .eth in the root registry
  await rootRegistry.register("eth", deployer.address, ethRegistry.address, ethers.constants.AddressZero, deployerRoles, maxExpiry);
  console.log("Registered .eth in the root registry");
  
  // Register .xyz in the root registry
  await rootRegistry.register("xyz", deployer.address, xyzRegistry.address, ethers.constants.AddressZero, deployerRoles, maxExpiry);
  console.log("Registered .xyz in the root registry");
  
  // Register example.eth in the ETH registry
  await ethRegistry.register("example", deployer.address, exampleRegistry.address, ethers.constants.AddressZero, deployerRoles, maxExpiry);
  console.log("Registered example.eth in the ETH registry");
  
  // Register example.xyz in the XYZ registry (pointing to the same registry as example.eth)
  await xyzRegistry.register("example", deployer.address, exampleRegistry.address, ethers.constants.AddressZero, deployerRoles, maxExpiry);
  console.log("Registered example.xyz in the XYZ registry (aliasing to example.eth)");

  // Deploy a resolver for example.eth
  const resolverAddress = await exampleRegistry.deployResolver("example", deployer.address);
  console.log("Deployed resolver for example.eth at:", resolverAddress);

  // Set up the resolver with an ETH address
  const resolver = await SingleNameResolver.attach(resolverAddress);
  await resolver.setAddr("0x1234567890123456789012345678901234567890");
  console.log("Set ETH address for example.eth");
  
  // Set up the resolver with a text record
  await resolver.setText("email", "test@example.com");
  console.log("Set email text record for example.eth");
  
  // Set up the resolver with a content hash
  await resolver.setContenthash("0x1234567890");
  console.log("Set content hash for example.eth");

  // Deploy the universal resolver
  const UniversalResolverV2 = await ethers.getContractFactory("UniversalResolverV2");
  const universalResolver = await UniversalResolverV2.deploy(rootRegistry.address, []);
  await universalResolver.deployed();
  console.log("UniversalResolverV2 deployed to:", universalResolver.address);

  // Test resolving example.eth
  const encodedNameEth = dnsEncodeName("example.eth");
  const addrSelector = "0x3b3b57de"; // addr(bytes32)
  const [resultEth, resolverAddrEth] = await universalResolver.resolve(encodedNameEth, addrSelector);
  console.log("Resolved example.eth to:", resultEth);
  console.log("Using resolver:", resolverAddrEth);
  
  // Test resolving example.xyz
  const encodedNameXyz = dnsEncodeName("example.xyz");
  const [resultXyz, resolverAddrXyz] = await universalResolver.resolve(encodedNameXyz, addrSelector);
  console.log("Resolved example.xyz to:", resultXyz);
  console.log("Using resolver:", resolverAddrXyz);
  
  console.log("Deployment and setup complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
