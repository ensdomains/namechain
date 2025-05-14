const hre = require("hardhat");
const fs = require("fs");
const path = require("path");
const { ethers } = require("hardhat");
const { VerifiableFactory } = require("./utils/verifiable-factory");

async function main() {
  console.log("Deploying SimplifiedHybridResolver and associated contracts...");
  
  const [deployer] = await ethers.getSigners();
  console.log(`Deployer address: ${deployer.address}`);
  
  const RegistryDatastore = await ethers.getContractFactory("RegistryDatastore");
  const registryDatastore = await RegistryDatastore.deploy();
  await registryDatastore.deployed();
  console.log(`RegistryDatastore deployed to: ${registryDatastore.address}`);
  
  const RootRegistry = await ethers.getContractFactory("RootRegistry");
  const rootRegistry = await RootRegistry.deploy(registryDatastore.address);
  await rootRegistry.deployed();
  console.log(`RootRegistry deployed to: ${rootRegistry.address}`);
  
  const ETHRegistry = await ethers.getContractFactory("ETHRegistry");
  const ethRegistry = await ETHRegistry.deploy(registryDatastore.address);
  await ethRegistry.deployed();
  console.log(`ETHRegistry deployed to: ${ethRegistry.address}`);
  
  const XYZRegistry = await ethers.getContractFactory("ETHRegistry");
  const xyzRegistry = await XYZRegistry.deploy(registryDatastore.address);
  await xyzRegistry.deployed();
  console.log(`XYZRegistry (clone of ETHRegistry) deployed to: ${xyzRegistry.address}`);
  
  const VerifiableFactoryContract = await ethers.getContractFactory("VerifiableFactory");
  const verifiableFactory = await VerifiableFactoryContract.deploy();
  await verifiableFactory.deployed();
  console.log(`VerifiableFactory deployed to: ${verifiableFactory.address}`);
  
  const factory = new VerifiableFactory(verifiableFactory, deployer);
  
  const SimplifiedHybridResolver = await ethers.getContractFactory("SimplifiedHybridResolver");
  const simplifiedHybridResolverImpl = await SimplifiedHybridResolver.deploy();
  await simplifiedHybridResolverImpl.deployed();
  console.log(`SimplifiedHybridResolver implementation deployed to: ${simplifiedHybridResolverImpl.address}`);
  
  const OwnedResolver = await ethers.getContractFactory("OwnedResolver");
  const ownedResolverImpl = await OwnedResolver.deploy();
  await ownedResolverImpl.deployed();
  console.log(`OwnedResolver implementation deployed to: ${ownedResolverImpl.address}`);
  
  const UniversalResolver = await ethers.getContractFactory("UniversalResolver");
  const universalResolver = await UniversalResolver.deploy(rootRegistry.address, []);
  await universalResolver.deployed();
  console.log(`UniversalResolver deployed to: ${universalResolver.address}`);
  
  await rootRegistry.registerTLD("eth", ethRegistry.address);
  console.log("Registered .eth TLD in RootRegistry");
  
  await rootRegistry.registerTLD("xyz", xyzRegistry.address);
  console.log("Registered .xyz TLD in RootRegistry");
  
  const ethResolverProxy = await factory.deploy(
    simplifiedHybridResolverImpl.address,
    SimplifiedHybridResolver.interface.encodeFunctionData("initialize", [deployer.address, rootRegistry.address])
  );
  console.log(`ETH SimplifiedHybridResolver proxy deployed to: ${ethResolverProxy.address}`);
  const ethResolver = SimplifiedHybridResolver.attach(ethResolverProxy.address);
  
  await ethRegistry.setResolver("", ethResolverProxy.address);
  console.log("Set resolver for .eth");
  
  await ethResolver.setAddr(
    "0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae", // namehash of eth
    "0x5555555555555555555555555555555555555555"
  );
  console.log("Set ETH address for .eth");
  
  const xyzResolverProxy = await factory.deploy(
    simplifiedHybridResolverImpl.address,
    SimplifiedHybridResolver.interface.encodeFunctionData("initialize", [deployer.address, rootRegistry.address])
  );
  console.log(`XYZ SimplifiedHybridResolver proxy deployed to: ${xyzResolverProxy.address}`);
  const xyzResolver = SimplifiedHybridResolver.attach(xyzResolverProxy.address);
  
  await xyzRegistry.setResolver("", xyzResolverProxy.address);
  console.log("Set resolver for .xyz");
  
  await xyzResolver.setAddr(
    "0x9dd2c369a187b4e6b9c402f030e50743e619301ea62aa4c0737d4ef7e10a3d49", // namehash of xyz
    "0x6666666666666666666666666666666666666666"
  );
  console.log("Set ETH address for .xyz");
  
  await ethRegistry.register("example");
  console.log("Registered example.eth");
  
  const ExampleRegistry = await ethers.getContractFactory("ETHRegistry");
  const exampleRegistry = await ExampleRegistry.deploy(registryDatastore.address);
  await exampleRegistry.deployed();
  console.log(`Example.eth subregistry deployed to: ${exampleRegistry.address}`);
  
  await ethRegistry.setSubregistry("example", exampleRegistry.address);
  console.log("Set subregistry for example.eth");
  
  const sharedResolverProxy = await factory.deploy(
    simplifiedHybridResolverImpl.address,
    SimplifiedHybridResolver.interface.encodeFunctionData("initialize", [deployer.address, rootRegistry.address])
  );
  console.log(`Shared SimplifiedHybridResolver proxy deployed to: ${sharedResolverProxy.address}`);
  const sharedResolver = SimplifiedHybridResolver.attach(sharedResolverProxy.address);
  
  await ethRegistry.setResolver("example", sharedResolverProxy.address);
  console.log("Set resolver for example.eth");
  
  await xyzRegistry.register("example");
  console.log("Registered example.xyz");
  
  await xyzRegistry.setResolver("example", sharedResolverProxy.address);
  console.log("Set resolver for example.xyz (same as example.eth for aliasing)");
  
  const namehashExampleEth = "0xde9b09fd7c5f901e23a3f19fecc54828e9c848539801e86591bd9801b019f84f";
  const namehashExampleXyz = "0x7d56aa46358ba2f8b77d8e05bcabdd2358370dcf34e87810f8cea77ecb3fc57d";
  
  await sharedResolver.setAddr(
    namehashExampleEth,
    "0x1234567890123456789012345678901234567890"
  );
  console.log("Set ETH address for example.eth");
  
  await sharedResolver.mapToExistingLabelHash(
    namehashExampleXyz,
    await sharedResolver.getLabelHash(namehashExampleEth)
  );
  console.log("Mapped example.xyz to the same label hash as example.eth (for aliasing)");
  
  await exampleRegistry.register("foo");
  console.log("Registered foo.example.eth");
  
  const fooResolverProxy = await factory.deploy(
    simplifiedHybridResolverImpl.address,
    SimplifiedHybridResolver.interface.encodeFunctionData("initialize", [deployer.address, rootRegistry.address])
  );
  console.log(`Foo.example.eth SimplifiedHybridResolver proxy deployed to: ${fooResolverProxy.address}`);
  const fooResolver = SimplifiedHybridResolver.attach(fooResolverProxy.address);
  
  await exampleRegistry.setResolver("foo", fooResolverProxy.address);
  console.log("Set resolver for foo.example.eth");
  
  await fooResolver.setAddr(
    "0x1bf8f14d97ecf08078cca34388b213811f982710a2b14df4a7c07f46429b3bf9", // namehash of foo.example.eth
    "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"
  );
  console.log("Set ETH address for foo.example.eth");
  
  console.log("\nMeasuring gas costs for comparison:");
  
  const testHybridResolverProxy = await factory.deploy(
    simplifiedHybridResolverImpl.address,
    SimplifiedHybridResolver.interface.encodeFunctionData("initialize", [deployer.address, rootRegistry.address])
  );
  const testHybridResolver = SimplifiedHybridResolver.attach(testHybridResolverProxy.address);
  
  const testOwnedResolverProxy = await factory.deploy(
    ownedResolverImpl.address,
    OwnedResolver.interface.encodeFunctionData("initialize", [deployer.address])
  );
  const testOwnedResolver = OwnedResolver.attach(testOwnedResolverProxy.address);
  
  const testNode = ethers.utils.namehash("test.eth");
  
  const hybridSetTx = await testHybridResolver.setAddr(
    testNode,
    "0x1111111111111111111111111111111111111111"
  );
  const hybridSetReceipt = await hybridSetTx.wait();
  const hybridSetGas = hybridSetReceipt.gasUsed.toString();
  console.log(`SimplifiedHybridResolver.setAddr: ${hybridSetGas} gas`);
  
  const ownedSetTx = await testOwnedResolver.setAddr(
    testNode,
    "0x1111111111111111111111111111111111111111"
  );
  const ownedSetReceipt = await ownedSetTx.wait();
  const ownedSetGas = ownedSetReceipt.gasUsed.toString();
  console.log(`OwnedResolver.setAddr: ${ownedSetGas} gas`);
  
  const setDiff = parseInt(hybridSetGas) - parseInt(ownedSetGas);
  const setDiffPercent = (setDiff / parseInt(ownedSetGas) * 100).toFixed(2);
  console.log(`Difference: ${setDiff} gas (${setDiffPercent}%)`);
  
  const hybridGetTx = await testHybridResolver.estimateGas.addr(testNode);
  console.log(`SimplifiedHybridResolver.addr: ${hybridGetTx.toString()} gas`);
  
  const ownedGetTx = await testOwnedResolver.estimateGas.addr(testNode);
  console.log(`OwnedResolver.addr: ${ownedGetTx.toString()} gas`);
  
  const getDiff = parseInt(hybridGetTx.toString()) - parseInt(ownedGetTx.toString());
  const getDiffPercent = (getDiff / parseInt(ownedGetTx.toString()) * 100).toFixed(2);
  console.log(`Difference: ${getDiff} gas (${getDiffPercent}%)`);
  
  const envContent = `
ROOT_REGISTRY_ADDRESS=${rootRegistry.address}
ETH_REGISTRY_ADDRESS=${ethRegistry.address}
XYZ_REGISTRY_ADDRESS=${xyzRegistry.address}
EXAMPLE_REGISTRY_ADDRESS=${exampleRegistry.address}
ETH_RESOLVER_ADDRESS=${ethResolver.address}
XYZ_RESOLVER_ADDRESS=${xyzResolver.address}
SHARED_RESOLVER_ADDRESS=${sharedResolver.address}
FOO_RESOLVER_ADDRESS=${fooResolver.address}
UNIVERSAL_RESOLVER_ADDRESS=${universalResolver.address}
`;
  
  fs.writeFileSync(path.join(__dirname, "..", ".env"), envContent);
  console.log("Wrote deployment addresses to .env file");
  
  console.log("\nDeployment complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
