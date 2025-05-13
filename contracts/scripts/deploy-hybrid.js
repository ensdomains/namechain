import hardhat from "hardhat";
const { ethers } = hardhat;
import * as fs from "fs/promises";
import * as path from "path";
import * as dotenv from "dotenv";

const ENV_FILE_PATH = path.resolve(process.cwd(), '.env');
dotenv.config({ path: ENV_FILE_PATH });

async function main() {
  console.log("Deploying contracts to hardhat node...");
  
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  
  console.log("Deploying RegistryDatastore...");
  const RegistryDatastore = await ethers.getContractFactory("RegistryDatastore");
  const datastore = await RegistryDatastore.deploy();
  await datastore.deployed();
  console.log("RegistryDatastore deployed to:", datastore.address);
  
  console.log("Deploying RootRegistry...");
  const RootRegistry = await ethers.getContractFactory("RootRegistry");
  const rootRegistry = await RootRegistry.deploy(datastore.address);
  await rootRegistry.waitForDeployment();
  console.log("RootRegistry deployed to:", await rootRegistry.getAddress());
  
  console.log("Deploying ETHRegistry...");
  const PermissionedRegistry = await ethers.getContractFactory("PermissionedRegistry");
  const ethRegistry = await PermissionedRegistry.deploy(datastore.address);
  await ethRegistry.waitForDeployment();
  console.log("ETHRegistry deployed to:", await ethRegistry.getAddress());
  
  console.log("Deploying HybridResolver implementation...");
  const HybridResolver = await ethers.getContractFactory("HybridResolver");
  const hybridResolverImpl = await HybridResolver.deploy();
  await hybridResolverImpl.waitForDeployment();
  console.log("HybridResolver implementation deployed to:", await hybridResolverImpl.getAddress());
  
  console.log("Deploying UniversalResolver...");
  const UniversalResolver = await ethers.getContractFactory("UniversalResolver");
  const universalResolver = await UniversalResolver.deploy(await rootRegistry.getAddress(), []);
  await universalResolver.waitForDeployment();
  console.log("UniversalResolver deployed to:", await universalResolver.getAddress());
  
  console.log("Registering .eth TLD...");
  await rootRegistry.registerSubname("eth", deployer.address);
  console.log("Registered .eth TLD");
  
  console.log("Setting ETHRegistry as subregistry for .eth...");
  const ethLabelHash = ethers.keccak256(ethers.toUtf8Bytes("eth"));
  await datastore.setSubregistry(ethLabelHash, await ethRegistry.getAddress(), 0, 0);
  console.log("Set ETHRegistry as subregistry for .eth");
  
  console.log("Registering example.eth...");
  await ethRegistry.registerSubname("example", deployer.address);
  console.log("Registered example.eth");
  
  console.log("Deploying HybridResolver for example.eth...");
  const HybridResolverProxy = await ethers.getContractFactory("ERC1967Proxy");
  const exampleResolverProxy = await HybridResolverProxy.deploy(
    await hybridResolverImpl.getAddress(),
    HybridResolver.interface.encodeFunctionData("initialize", [deployer.address, await ethRegistry.getAddress()])
  );
  await exampleResolverProxy.waitForDeployment();
  const exampleResolver = HybridResolver.attach(await exampleResolverProxy.getAddress());
  console.log("HybridResolver for example.eth deployed to:", await exampleResolver.getAddress());
  
  console.log("Setting resolver for example.eth...");
  const exampleLabelHash = ethers.keccak256(ethers.toUtf8Bytes("example"));
  await datastore.setResolver(exampleLabelHash, await exampleResolver.getAddress(), 0, 0);
  console.log("Set resolver for example.eth");
  
  const exampleEthNamehash = calculateNamehash("example.eth");
  console.log("Namehash for example.eth:", exampleEthNamehash);
  
  console.log("Mapping namehash to labelHash in resolver...");
  await exampleResolver.mapNamehash(exampleEthNamehash, exampleLabelHash, true);
  console.log("Mapped namehash to labelHash");
  
  console.log("Setting address for example.eth...");
  await exampleResolver.setAddr(exampleEthNamehash, "0x1234567890123456789012345678901234567890");
  console.log("Set address for example.eth");
  
  console.log("Registering foo.example.eth...");
  const exampleRegistry = await PermissionedRegistry.deploy(datastore.address);
  await exampleRegistry.waitForDeployment();
  console.log("Example subregistry deployed to:", await exampleRegistry.getAddress());
  
  await datastore.setSubregistry(exampleLabelHash, await exampleRegistry.getAddress(), 0, 0);
  console.log("Set subregistry for example.eth");
  
  await exampleRegistry.registerSubname("foo", deployer.address);
  console.log("Registered foo.example.eth");
  
  console.log("Deploying HybridResolver for foo.example.eth...");
  const fooResolverProxy = await HybridResolverProxy.deploy(
    await hybridResolverImpl.getAddress(),
    HybridResolver.interface.encodeFunctionData("initialize", [deployer.address, await exampleRegistry.getAddress()])
  );
  await fooResolverProxy.waitForDeployment();
  const fooResolver = HybridResolver.attach(await fooResolverProxy.getAddress());
  console.log("HybridResolver for foo.example.eth deployed to:", await fooResolver.getAddress());
  
  console.log("Setting resolver for foo.example.eth...");
  const fooLabelHash = ethers.keccak256(ethers.toUtf8Bytes("foo"));
  await datastore.setResolver(fooLabelHash, await fooResolver.getAddress(), 0, 0);
  console.log("Set resolver for foo.example.eth");
  
  const fooExampleEthNamehash = calculateNamehash("foo.example.eth");
  console.log("Namehash for foo.example.eth:", fooExampleEthNamehash);
  
  console.log("Mapping namehash to labelHash in resolver...");
  await fooResolver.mapNamehash(fooExampleEthNamehash, fooLabelHash, true);
  console.log("Mapped namehash to labelHash");
  
  console.log("Setting address for foo.example.eth...");
  await fooResolver.setAddr(fooExampleEthNamehash, "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd");
  console.log("Set address for foo.example.eth");
  
  console.log("Registering .xyz TLD...");
  await rootRegistry.registerSubname("xyz", deployer.address);
  console.log("Registered .xyz TLD");
  
  console.log("Deploying XYZRegistry...");
  const xyzRegistry = await PermissionedRegistry.deploy(datastore.address);
  await xyzRegistry.waitForDeployment();
  console.log("XYZRegistry deployed to:", await xyzRegistry.getAddress());
  
  console.log("Setting XYZRegistry as subregistry for .xyz...");
  const xyzLabelHash = ethers.keccak256(ethers.toUtf8Bytes("xyz"));
  await datastore.setSubregistry(xyzLabelHash, await xyzRegistry.getAddress(), 0, 0);
  console.log("Set XYZRegistry as subregistry for .xyz");
  
  console.log("Registering example.xyz...");
  await xyzRegistry.registerSubname("example", deployer.address);
  console.log("Registered example.xyz");
  
  const exampleXyzNamehash = calculateNamehash("example.xyz");
  console.log("Namehash for example.xyz:", exampleXyzNamehash);
  
  console.log("Mapping example.xyz namehash to same labelHash as example.eth...");
  await exampleResolver.mapNamehash(exampleXyzNamehash, exampleLabelHash, false);
  console.log("Mapped example.xyz namehash to same labelHash as example.eth");
  
  console.log("Setting resolver for example.xyz...");
  const exampleXyzLabelHash = ethers.keccak256(ethers.toUtf8Bytes("example"));
  await datastore.setResolver(exampleXyzLabelHash, await exampleResolver.getAddress(), 0, 0);
  console.log("Set resolver for example.xyz");
  
  console.log("Writing deployment addresses to .env file...");
  const envContent = `
# Deployment addresses
DEPLOYER_ADDRESS=${deployer.address}
REGISTRY_DATASTORE_ADDRESS=${datastore.address}
ROOT_REGISTRY_ADDRESS=${rootRegistry.address}
ETH_REGISTRY_ADDRESS=${ethRegistry.address}
XYZ_REGISTRY_ADDRESS=${xyzRegistry.address}
EXAMPLE_REGISTRY_ADDRESS=${exampleRegistry.address}
UNIVERSAL_RESOLVER_ADDRESS=${universalResolver.address}
HYBRID_RESOLVER_IMPLEMENTATION=${hybridResolverImpl.address}
EXAMPLE_RESOLVER_ADDRESS=${exampleResolver.address}
FOO_RESOLVER_ADDRESS=${fooResolver.address}
`;
  
  await fs.writeFile(ENV_FILE_PATH, envContent);
  console.log("Deployment addresses written to .env file");
  
  console.log("Deployment complete!");
}

function calculateNamehash(name) {
  if (!name) return '0x0000000000000000000000000000000000000000000000000000000000000000';
  
  const labels = name.split('.');
  let node = '0x0000000000000000000000000000000000000000000000000000000000000000';
  
  for (let i = labels.length - 1; i >= 0; i--) {
    const labelHash = ethers.keccak256(ethers.toUtf8Bytes(labels[i]));
    node = ethers.keccak256(ethers.concat([node, labelHash]));
  }
  
  return node;
}

export default main;

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
