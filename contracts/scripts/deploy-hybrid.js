const hre = require("hardhat");
const fs = require("fs").promises;
const path = require("path");
const dotenv = require("dotenv");

const ENV_FILE_PATH = path.resolve(process.cwd(), '.env');
dotenv.config({ path: ENV_FILE_PATH });

async function main() {
  console.log("Deploying contracts to hardhat node...");
  
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  
  console.log("Deploying RegistryDatastore...");
  const RegistryDatastore = await hre.ethers.getContractFactory("RegistryDatastore");
  const datastore = await RegistryDatastore.deploy();
  await datastore.deployed();
  console.log("RegistryDatastore deployed to:", datastore.address);
  
  console.log("Deploying RootRegistry...");
  const RootRegistry = await hre.ethers.getContractFactory("RootRegistry");
  const rootRegistry = await RootRegistry.deploy(datastore.address);
  await rootRegistry.deployed();
  console.log("RootRegistry deployed to:", rootRegistry.address);
  
  console.log("Deploying ETHRegistry...");
  const PermissionedRegistry = await hre.ethers.getContractFactory("PermissionedRegistry");
  const ethRegistry = await PermissionedRegistry.deploy(datastore.address);
  await ethRegistry.deployed();
  console.log("ETHRegistry deployed to:", ethRegistry.address);
  
  console.log("Deploying HybridResolver implementation...");
  const HybridResolver = await hre.ethers.getContractFactory("HybridResolver");
  const hybridResolverImpl = await HybridResolver.deploy();
  await hybridResolverImpl.deployed();
  console.log("HybridResolver implementation deployed to:", hybridResolverImpl.address);
  
  console.log("Deploying UniversalResolver...");
  const UniversalResolver = await hre.ethers.getContractFactory("UniversalResolver");
  const universalResolver = await UniversalResolver.deploy(rootRegistry.address, []);
  await universalResolver.deployed();
  console.log("UniversalResolver deployed to:", universalResolver.address);
  
  console.log("Registering .eth TLD...");
  await rootRegistry.registerSubname("eth", deployer.address);
  console.log("Registered .eth TLD");
  
  console.log("Setting ETHRegistry as subregistry for .eth...");
  const ethLabelHash = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes("eth"));
  await datastore.setSubregistry(ethLabelHash, ethRegistry.address, 0, 0);
  console.log("Set ETHRegistry as subregistry for .eth");
  
  console.log("Registering example.eth...");
  await ethRegistry.registerSubname("example", deployer.address);
  console.log("Registered example.eth");
  
  console.log("Deploying HybridResolver for example.eth...");
  const HybridResolverProxy = await hre.ethers.getContractFactory("ERC1967Proxy");
  const exampleResolverProxy = await HybridResolverProxy.deploy(
    hybridResolverImpl.address,
    HybridResolver.interface.encodeFunctionData("initialize", [deployer.address, ethRegistry.address])
  );
  await exampleResolverProxy.deployed();
  const exampleResolver = HybridResolver.attach(exampleResolverProxy.address);
  console.log("HybridResolver for example.eth deployed to:", exampleResolver.address);
  
  console.log("Setting resolver for example.eth...");
  const exampleLabelHash = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes("example"));
  await datastore.setResolver(exampleLabelHash, exampleResolver.address, 0, 0);
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
  await exampleRegistry.deployed();
  console.log("Example subregistry deployed to:", exampleRegistry.address);
  
  await datastore.setSubregistry(exampleLabelHash, exampleRegistry.address, 0, 0);
  console.log("Set subregistry for example.eth");
  
  await exampleRegistry.registerSubname("foo", deployer.address);
  console.log("Registered foo.example.eth");
  
  console.log("Deploying HybridResolver for foo.example.eth...");
  const fooResolverProxy = await HybridResolverProxy.deploy(
    hybridResolverImpl.address,
    HybridResolver.interface.encodeFunctionData("initialize", [deployer.address, exampleRegistry.address])
  );
  await fooResolverProxy.deployed();
  const fooResolver = HybridResolver.attach(fooResolverProxy.address);
  console.log("HybridResolver for foo.example.eth deployed to:", fooResolver.address);
  
  console.log("Setting resolver for foo.example.eth...");
  const fooLabelHash = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes("foo"));
  await datastore.setResolver(fooLabelHash, fooResolver.address, 0, 0);
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
  await xyzRegistry.deployed();
  console.log("XYZRegistry deployed to:", xyzRegistry.address);
  
  console.log("Setting XYZRegistry as subregistry for .xyz...");
  const xyzLabelHash = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes("xyz"));
  await datastore.setSubregistry(xyzLabelHash, xyzRegistry.address, 0, 0);
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
  const exampleXyzLabelHash = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes("example"));
  await datastore.setResolver(exampleXyzLabelHash, exampleResolver.address, 0, 0);
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
    const labelHash = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes(labels[i]));
    node = hre.ethers.utils.keccak256(hre.ethers.utils.concat([node, labelHash]));
  }
  
  return node;
}

module.exports = main;

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}
