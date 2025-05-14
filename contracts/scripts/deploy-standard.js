import hre from "hardhat";
import fs from "fs";
import path from "path";
import hardhat from "hardhat";
const { ethers } = hardhat;
import { VerifiableFactory } from "./utils/verifiable-factory.js";

async function main() {
  console.log("Deploying ENSStandardResolver and associated contracts...");
  
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
  
  const ENSStandardResolver = await ethers.getContractFactory("ENSStandardResolver");
  const ensStandardResolverImpl = await ENSStandardResolver.deploy();
  await ensStandardResolverImpl.deployed();
  console.log(`ENSStandardResolver implementation deployed to: ${ensStandardResolverImpl.address}`);
  
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
    ensStandardResolverImpl.address,
    ENSStandardResolver.interface.encodeFunctionData("initialize", [deployer.address, rootRegistry.address])
  );
  console.log(`ETH ENSStandardResolver proxy deployed to: ${ethResolverProxy.address}`);
  const ethResolver = ENSStandardResolver.attach(ethResolverProxy.address);
  
  await ethRegistry.setResolver("", ethResolverProxy.address);
  console.log("Set resolver for .eth");
  
  const ethNamehash = ethers.utils.namehash("eth");
  await ethResolver.setAddrWithLabel(
    ethNamehash,
    "eth", // Label string
    "0x5555555555555555555555555555555555555555"
  );
  console.log("Set ETH address for .eth");
  
  const xyzResolverProxy = await factory.deploy(
    ensStandardResolverImpl.address,
    ENSStandardResolver.interface.encodeFunctionData("initialize", [deployer.address, rootRegistry.address])
  );
  console.log(`XYZ ENSStandardResolver proxy deployed to: ${xyzResolverProxy.address}`);
  const xyzResolver = ENSStandardResolver.attach(xyzResolverProxy.address);
  
  await xyzRegistry.setResolver("", xyzResolverProxy.address);
  console.log("Set resolver for .xyz");
  
  const xyzNamehash = ethers.utils.namehash("xyz");
  await xyzResolver.setAddrWithLabel(
    xyzNamehash,
    "xyz", // Label string
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
    ensStandardResolverImpl.address,
    ENSStandardResolver.interface.encodeFunctionData("initialize", [deployer.address, rootRegistry.address])
  );
  console.log(`Shared ENSStandardResolver proxy deployed to: ${sharedResolverProxy.address}`);
  const sharedResolver = ENSStandardResolver.attach(sharedResolverProxy.address);
  
  await ethRegistry.setResolver("example", sharedResolverProxy.address);
  console.log("Set resolver for example.eth");
  
  await xyzRegistry.register("example");
  console.log("Registered example.xyz");
  
  await xyzRegistry.setResolver("example", sharedResolverProxy.address);
  console.log("Set resolver for example.xyz (same as example.eth for aliasing)");
  
  const namehashExampleEth = ethers.utils.namehash("example.eth");
  const namehashExampleXyz = ethers.utils.namehash("example.xyz");
  
  await sharedResolver.setAddrWithLabel(
    namehashExampleEth,
    "example", // Label string
    "0x1234567890123456789012345678901234567890"
  );
  console.log("Set ETH address for example.eth");
  
  await sharedResolver.mapToExistingLabel(
    namehashExampleXyz,
    "example" // Target label string
  );
  console.log("Mapped example.xyz to the same label as example.eth (for aliasing)");
  
  await exampleRegistry.register("foo");
  console.log("Registered foo.example.eth");
  
  const fooResolverProxy = await factory.deploy(
    ensStandardResolverImpl.address,
    ENSStandardResolver.interface.encodeFunctionData("initialize", [deployer.address, rootRegistry.address])
  );
  console.log(`Foo.example.eth ENSStandardResolver proxy deployed to: ${fooResolverProxy.address}`);
  const fooResolver = ENSStandardResolver.attach(fooResolverProxy.address);
  
  await exampleRegistry.setResolver("foo", fooResolverProxy.address);
  console.log("Set resolver for foo.example.eth");
  
  const namehashFooExampleEth = ethers.utils.namehash("foo.example.eth");
  await fooResolver.setAddrWithLabel(
    namehashFooExampleEth,
    "foo", // Label string
    "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"
  );
  console.log("Set ETH address for foo.example.eth");
  
  console.log("\nMeasuring gas costs for comparison:");
  
  const testStandardResolverProxy = await factory.deploy(
    ensStandardResolverImpl.address,
    ENSStandardResolver.interface.encodeFunctionData("initialize", [deployer.address, rootRegistry.address])
  );
  const testStandardResolver = ENSStandardResolver.attach(testStandardResolverProxy.address);
  
  const testOwnedResolverProxy = await factory.deploy(
    ownedResolverImpl.address,
    OwnedResolver.interface.encodeFunctionData("initialize", [deployer.address])
  );
  const testOwnedResolver = OwnedResolver.attach(testOwnedResolverProxy.address);
  
  const testNode = ethers.utils.namehash("test.eth");
  
  const standardSetTx = await testStandardResolver.setAddrWithLabel(
    testNode,
    "test", // Label string
    "0x1111111111111111111111111111111111111111"
  );
  const standardSetReceipt = await standardSetTx.wait();
  const standardSetGas = standardSetReceipt.gasUsed.toString();
  console.log(`ENSStandardResolver.setAddrWithLabel: ${standardSetGas} gas`);
  
  const ownedSetTx = await testOwnedResolver.setAddr(
    testNode,
    "0x1111111111111111111111111111111111111111"
  );
  const ownedSetReceipt = await ownedSetTx.wait();
  const ownedSetGas = ownedSetReceipt.gasUsed.toString();
  console.log(`OwnedResolver.setAddr: ${ownedSetGas} gas`);
  
  const setDiff = parseInt(standardSetGas) - parseInt(ownedSetGas);
  const setDiffPercent = (setDiff / parseInt(ownedSetGas) * 100).toFixed(2);
  console.log(`Difference: ${setDiff} gas (${setDiffPercent}%)`);
  
  const standardGetTx = await testStandardResolver.estimateGas.addr(testNode);
  console.log(`ENSStandardResolver.addr: ${standardGetTx.toString()} gas`);
  
  const ownedGetTx = await testOwnedResolver.estimateGas.addr(testNode);
  console.log(`OwnedResolver.addr: ${ownedGetTx.toString()} gas`);
  
  const getDiff = parseInt(standardGetTx.toString()) - parseInt(ownedGetTx.toString());
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

try {
  await main();
  process.exit(0);
} catch (error) {
  console.error(error);
  process.exit(1);
}
