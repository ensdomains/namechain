import hre from "hardhat";
import fs from "fs";
import path from "path";
import {
  namehash,
  keccak256,
  stringToBytes,
  encodeAbiParameters,
  parseAbiParameters,
  concat,
  toBytes,
} from "viem";
import { VerifiableFactory } from "./utils/verifiable-factory.mjs";

async function main() {
  console.log("Deploying ENSStandardResolver and associated contracts...");
  
  const publicClient = await hre.viem.getPublicClient();
  const [walletClient] = await hre.viem.getWalletClients();
  console.log(`Deployer address: ${walletClient.account.address}`);
  
  const registryDatastore = await hre.viem.deployContract("RegistryDatastore");
  console.log(`RegistryDatastore deployed to: ${registryDatastore.address}`);
  
  const rootRegistry = await hre.viem.deployContract("RootRegistry", [registryDatastore.address]);
  console.log(`RootRegistry deployed to: ${rootRegistry.address}`);
  
  const ethRegistry = await hre.viem.deployContract("ETHRegistry", [registryDatastore.address]);
  console.log(`ETHRegistry deployed to: ${ethRegistry.address}`);
  
  const xyzRegistry = await hre.viem.deployContract("ETHRegistry", [registryDatastore.address]);
  console.log(`XYZRegistry (clone of ETHRegistry) deployed to: ${xyzRegistry.address}`);
  
  const verifiableFactory = await hre.viem.deployContract("VerifiableFactory");
  console.log(`VerifiableFactory deployed to: ${verifiableFactory.address}`);
  
  const factory = new VerifiableFactory(verifiableFactory, walletClient);
  
  const ensStandardResolverImpl = await hre.viem.deployContract("ENSStandardResolver");
  console.log(`ENSStandardResolver implementation deployed to: ${ensStandardResolverImpl.address}`);
  
  const ownedResolverImpl = await hre.viem.deployContract("OwnedResolver");
  console.log(`OwnedResolver implementation deployed to: ${ownedResolverImpl.address}`);
  
  const universalResolver = await hre.viem.deployContract("UniversalResolver", [rootRegistry.address, []]);
  console.log(`UniversalResolver deployed to: ${universalResolver.address}`);
  
  await rootRegistry.write.registerTLD(["eth", ethRegistry.address], { account: walletClient.account });
  console.log("Registered .eth TLD in RootRegistry");
  
  await rootRegistry.write.registerTLD(["xyz", xyzRegistry.address], { account: walletClient.account });
  console.log("Registered .xyz TLD in RootRegistry");
  
  // Encode initialization data for ENSStandardResolver
  const initData = encodeAbiParameters(
    parseAbiParameters('address owner, address rootRegistry'),
    [walletClient.account.address, rootRegistry.address]
  );
  
  const ethResolverProxy = await factory.deploy(
    ensStandardResolverImpl.address,
    concat([toBytes('0x8129fc1c'), initData]) // 0x8129fc1c is the function selector for initialize()
  );
  console.log(`ETH ENSStandardResolver proxy deployed to: ${ethResolverProxy.address}`);
  const ethResolver = await hre.viem.getContractAt("ENSStandardResolver", ethResolverProxy.address);
  
  await ethRegistry.write.setResolver(["", ethResolverProxy.address], { account: walletClient.account });
  console.log("Set resolver for .eth");
  
  const ethNamehash = namehash("eth");
  await ethResolver.write.setAddrWithLabel(
    [ethNamehash, "eth", "0x5555555555555555555555555555555555555555"],
    { account: walletClient.account }
  );
  console.log("Set ETH address for .eth");
  
  // Reuse the same initialization data format for xyz resolver
  const xyzResolverProxy = await factory.deploy(
    ensStandardResolverImpl.address,
    concat([toBytes('0x8129fc1c'), initData]) // 0x8129fc1c is the function selector for initialize()
  );
  console.log(`XYZ ENSStandardResolver proxy deployed to: ${xyzResolverProxy.address}`);
  const xyzResolver = await hre.viem.getContractAt("ENSStandardResolver", xyzResolverProxy.address);
  
  await xyzRegistry.write.setResolver(["", xyzResolverProxy.address], { account: walletClient.account });
  console.log("Set resolver for .xyz");
  
  const xyzNamehash = namehash("xyz");
  await xyzResolver.write.setAddrWithLabel(
    [xyzNamehash, "xyz", "0x6666666666666666666666666666666666666666"],
    { account: walletClient.account }
  );
  console.log("Set ETH address for .xyz");
  
  await ethRegistry.write.register(["example"], { account: walletClient.account });
  console.log("Registered example.eth");
  
  const exampleRegistry = await hre.viem.deployContract("ETHRegistry", [registryDatastore.address]);
  console.log(`Example.eth subregistry deployed to: ${exampleRegistry.address}`);
  
  await ethRegistry.write.setSubregistry(["example", exampleRegistry.address], { account: walletClient.account });
  console.log("Set subregistry for example.eth");
  
  // Reuse the same initialization data format for shared resolver
  const sharedResolverProxy = await factory.deploy(
    ensStandardResolverImpl.address,
    concat([toBytes('0x8129fc1c'), initData]) // 0x8129fc1c is the function selector for initialize()
  );
  console.log(`Shared ENSStandardResolver proxy deployed to: ${sharedResolverProxy.address}`);
  const sharedResolver = await hre.viem.getContractAt("ENSStandardResolver", sharedResolverProxy.address);
  
  await ethRegistry.write.setResolver(["example", sharedResolverProxy.address], { account: walletClient.account });
  console.log("Set resolver for example.eth");
  
  await xyzRegistry.write.register(["example"], { account: walletClient.account });
  console.log("Registered example.xyz");
  
  await xyzRegistry.write.setResolver(["example", sharedResolverProxy.address], { account: walletClient.account });
  console.log("Set resolver for example.xyz (same as example.eth for aliasing)");
  
  const namehashExampleEth = namehash("example.eth");
  const namehashExampleXyz = namehash("example.xyz");
  
  await sharedResolver.write.setAddrWithLabel(
    [namehashExampleEth, "example", "0x1234567890123456789012345678901234567890"],
    { account: walletClient.account }
  );
  console.log("Set ETH address for example.eth");
  
  await sharedResolver.write.mapToExistingLabel(
    [namehashExampleXyz, "example"],
    { account: walletClient.account }
  );
  console.log("Mapped example.xyz to the same label as example.eth (for aliasing)");
  
  await exampleRegistry.write.register(["foo"], { account: walletClient.account });
  console.log("Registered foo.example.eth");
  
  // Reuse the same initialization data format for foo resolver
  const fooResolverProxy = await factory.deploy(
    ensStandardResolverImpl.address,
    concat([toBytes('0x8129fc1c'), initData]) // 0x8129fc1c is the function selector for initialize()
  );
  console.log(`Foo.example.eth ENSStandardResolver proxy deployed to: ${fooResolverProxy.address}`);
  const fooResolver = await hre.viem.getContractAt("ENSStandardResolver", fooResolverProxy.address);
  
  await exampleRegistry.write.setResolver(["foo", fooResolverProxy.address], { account: walletClient.account });
  console.log("Set resolver for foo.example.eth");
  
  const namehashFooExampleEth = namehash("foo.example.eth");
  await fooResolver.write.setAddrWithLabel(
    [namehashFooExampleEth, "foo", "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"],
    { account: walletClient.account }
  );
  console.log("Set ETH address for foo.example.eth");
  
  console.log("\nMeasuring gas costs for comparison:");
  
  // Encode initialization data for test resolvers
  const testStandardResolverProxy = await factory.deploy(
    ensStandardResolverImpl.address,
    concat([toBytes('0x8129fc1c'), initData]) // 0x8129fc1c is the function selector for initialize()
  );
  const testStandardResolver = await hre.viem.getContractAt("ENSStandardResolver", testStandardResolverProxy.address);
  
  // Encode initialization data for OwnedResolver
  const ownedResolverInitData = encodeAbiParameters(
    parseAbiParameters('address owner'),
    [walletClient.account.address]
  );
  
  const testOwnedResolverProxy = await factory.deploy(
    ownedResolverImpl.address,
    concat([toBytes('0x8129fc1c'), ownedResolverInitData]) // 0x8129fc1c is the function selector for initialize()
  );
  const testOwnedResolver = await hre.viem.getContractAt("OwnedResolver", testOwnedResolverProxy.address);
  
  const testNode = namehash("test.eth");
  
  // Gas measurement for standard resolver
  const standardSetTx = await testStandardResolver.write.setAddrWithLabel(
    [testNode, "test", "0x1111111111111111111111111111111111111111"],
    { account: walletClient.account }
  );
  const standardSetReceipt = await publicClient.waitForTransactionReceipt({ hash: standardSetTx });
  const standardSetGas = standardSetReceipt.gasUsed.toString();
  console.log(`ENSStandardResolver.setAddrWithLabel: ${standardSetGas} gas`);
  
  // Gas measurement for owned resolver
  const ownedSetTx = await testOwnedResolver.write.setAddr(
    [testNode, "0x1111111111111111111111111111111111111111"],
    { account: walletClient.account }
  );
  const ownedSetReceipt = await publicClient.waitForTransactionReceipt({ hash: ownedSetTx });
  const ownedSetGas = ownedSetReceipt.gasUsed.toString();
  console.log(`OwnedResolver.setAddr: ${ownedSetGas} gas`);
  
  const setDiff = parseInt(standardSetGas) - parseInt(ownedSetGas);
  const setDiffPercent = (setDiff / parseInt(ownedSetGas) * 100).toFixed(2);
  console.log(`Difference: ${setDiff} gas (${setDiffPercent}%)`);
  
  // Gas estimation for read operations
  const standardGetGas = await publicClient.estimateContractGas({
    address: testStandardResolver.address,
    abi: testStandardResolver.abi,
    functionName: 'addr',
    args: [testNode],
    account: walletClient.account
  });
  console.log(`ENSStandardResolver.addr: ${standardGetGas.toString()} gas`);
  
  const ownedGetGas = await publicClient.estimateContractGas({
    address: testOwnedResolver.address,
    abi: testOwnedResolver.abi,
    functionName: 'addr',
    args: [testNode],
    account: walletClient.account
  });
  console.log(`OwnedResolver.addr: ${ownedGetGas.toString()} gas`);
  
  const getDiff = parseInt(standardGetGas.toString()) - parseInt(ownedGetGas.toString());
  const getDiffPercent = (getDiff / parseInt(ownedGetGas.toString()) * 100).toFixed(2);
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
DATASTORE_ADDRESS=${registryDatastore.address}
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
