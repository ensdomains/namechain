import hre from "hardhat";
import fs from "fs";
import { ethers } from "hardhat";
import { dnsEncodeName } from "../test/utils/utils.js";

async function main() {
  console.log("Deploying Registry-Aware Resolver...");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  const RegistryDatastore = await ethers.getContractFactory("RegistryDatastore");
  const datastore = await RegistryDatastore.deploy();
  await datastore.deployed();
  console.log("RegistryDatastore deployed to:", datastore.address);

  const RootRegistry = await ethers.getContractFactory("RootRegistry");
  const rootRegistry = await RootRegistry.deploy(datastore.address);
  await rootRegistry.deployed();
  console.log("RootRegistry deployed to:", rootRegistry.address);

  const ETHRegistry = await ethers.getContractFactory("PermissionedRegistry");
  const ethRegistry = await ETHRegistry.deploy(datastore.address);
  await ethRegistry.deployed();
  console.log("ETHRegistry deployed to:", ethRegistry.address);

  const XYZRegistry = await ethers.getContractFactory("PermissionedRegistry");
  const xyzRegistry = await XYZRegistry.deploy(datastore.address);
  await xyzRegistry.deployed();
  console.log("XYZRegistry deployed to:", xyzRegistry.address);

  const VerifiableFactory = await ethers.getContractFactory("VerifiableFactory");
  const factory = await VerifiableFactory.deploy();
  await factory.deployed();
  console.log("VerifiableFactory deployed to:", factory.address);

  const RegistryAwareResolver = await ethers.getContractFactory("RegistryAwareResolver");
  const resolverImplementation = await RegistryAwareResolver.deploy();
  await resolverImplementation.deployed();
  console.log("RegistryAwareResolver implementation deployed to:", resolverImplementation.address);

  const OwnedResolver = await ethers.getContractFactory("OwnedResolver");
  const ownedResolverImplementation = await OwnedResolver.deploy();
  await ownedResolverImplementation.deployed();
  console.log("OwnedResolver implementation deployed to:", ownedResolverImplementation.address);

  const ethLabel = "eth";
  const ethLabelHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(ethLabel));
  await rootRegistry.setSubregistry(ethLabel, ethRegistry.address);
  console.log("Registered .eth in root registry");

  const xyzLabel = "xyz";
  const xyzLabelHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(xyzLabel));
  await rootRegistry.setSubregistry(xyzLabel, xyzRegistry.address);
  console.log("Registered .xyz in root registry");

  const ethResolverSalt = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("eth-resolver"));
  const ethResolverInitData = RegistryAwareResolver.interface.encodeFunctionData("initialize", [
    deployer.address,
    ethRegistry.address,
  ]);
  const ethResolverAddress = await factory.callStatic.deployProxy(
    resolverImplementation.address,
    ethResolverSalt,
    ethResolverInitData
  );
  await factory.deployProxy(resolverImplementation.address, ethResolverSalt, ethResolverInitData);
  console.log("ETH Resolver deployed to:", ethResolverAddress);

  const xyzResolverSalt = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("xyz-resolver"));
  const xyzResolverInitData = RegistryAwareResolver.interface.encodeFunctionData("initialize", [
    deployer.address,
    xyzRegistry.address,
  ]);
  const xyzResolverAddress = await factory.callStatic.deployProxy(
    resolverImplementation.address,
    xyzResolverSalt,
    xyzResolverInitData
  );
  await factory.deployProxy(resolverImplementation.address, xyzResolverSalt, xyzResolverInitData);
  console.log("XYZ Resolver deployed to:", xyzResolverAddress);

  await ethRegistry.setResolver(ethLabel, ethResolverAddress);
  console.log("Set resolver for .eth");
  await xyzRegistry.setResolver(xyzLabel, xyzResolverAddress);
  console.log("Set resolver for .xyz");

  const ethResolver = await ethers.getContractAt("RegistryAwareResolver", ethResolverAddress);
  
  const xyzResolver = await ethers.getContractAt("RegistryAwareResolver", xyzResolverAddress);

  const ExampleRegistry = await ethers.getContractFactory("PermissionedRegistry");
  const exampleRegistry = await ExampleRegistry.deploy(datastore.address);
  await exampleRegistry.deployed();
  console.log("Example Registry deployed to:", exampleRegistry.address);

  const exampleLabel = "example";
  await ethRegistry.setSubregistry(exampleLabel, exampleRegistry.address);
  console.log("Registered example.eth in ETH registry");

  await xyzRegistry.setSubregistry(exampleLabel, exampleRegistry.address);
  console.log("Registered example.xyz in XYZ registry (pointing to the same subregistry)");

  const exampleResolverSalt = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("example-resolver"));
  const exampleResolverInitData = RegistryAwareResolver.interface.encodeFunctionData("initialize", [
    deployer.address,
    exampleRegistry.address,
  ]);
  const exampleResolverAddress = await factory.callStatic.deployProxy(
    resolverImplementation.address,
    exampleResolverSalt,
    exampleResolverInitData
  );
  await factory.deployProxy(resolverImplementation.address, exampleResolverSalt, exampleResolverInitData);
  console.log("Example Resolver deployed to:", exampleResolverAddress);

  await exampleRegistry.setResolver(exampleLabel, exampleResolverAddress);
  console.log("Set resolver for example.eth/example.xyz");

  const exampleResolver = await ethers.getContractAt("RegistryAwareResolver", exampleResolverAddress);

  const namehashEth = ethers.utils.namehash("eth");
  const namehashXyz = ethers.utils.namehash("xyz");
  const namehashExampleEth = ethers.utils.namehash("example.eth");
  const namehashExampleXyz = ethers.utils.namehash("example.xyz");

  await ethResolver.setAddr(namehashEth, "0x5555555555555555555555555555555555555555");
  console.log("Set ETH address for .eth");
  await xyzResolver.setAddr(namehashXyz, "0x6666666666666666666666666666666666666666");
  console.log("Set ETH address for .xyz");
  await exampleResolver.setAddr(namehashExampleEth, "0x1234567890123456789012345678901234567890");
  console.log("Set ETH address for example.eth");

  const FooRegistry = await ethers.getContractFactory("PermissionedRegistry");
  const fooRegistry = await FooRegistry.deploy(datastore.address);
  await fooRegistry.deployed();
  console.log("Foo Registry deployed to:", fooRegistry.address);

  const fooLabel = "foo";
  await exampleRegistry.setSubregistry(fooLabel, fooRegistry.address);
  console.log("Registered foo.example.eth in example registry");

  const fooResolverSalt = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("foo-resolver"));
  const fooResolverInitData = RegistryAwareResolver.interface.encodeFunctionData("initialize", [
    deployer.address,
    fooRegistry.address,
  ]);
  const fooResolverAddress = await factory.callStatic.deployProxy(
    resolverImplementation.address,
    fooResolverSalt,
    fooResolverInitData
  );
  await factory.deployProxy(resolverImplementation.address, fooResolverSalt, fooResolverInitData);
  console.log("Foo Resolver deployed to:", fooResolverAddress);

  await fooRegistry.setResolver(fooLabel, fooResolverAddress);
  console.log("Set resolver for foo.example.eth");

  const fooResolver = await ethers.getContractAt("RegistryAwareResolver", fooResolverAddress);

  const namehashFooExampleEth = ethers.utils.namehash("foo.example.eth");

  await fooResolver.setAddr(namehashFooExampleEth, "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd");
  console.log("Set ETH address for foo.example.eth");

  console.log("\nMeasuring gas costs...");

  const setAddrTx = await exampleResolver.setAddr(namehashExampleEth, "0x1234567890123456789012345678901234567890");
  const setAddrReceipt = await setAddrTx.wait();
  console.log(`Gas used for setAddr with RegistryAwareResolver: ${setAddrReceipt.gasUsed.toString()}`);

  const getAddrGas = await ethers.provider.estimateGas({
    to: exampleResolverAddress,
    data: exampleResolver.interface.encodeFunctionData("addr", [namehashExampleEth]),
  });
  console.log(`Gas used for addr with RegistryAwareResolver: ${getAddrGas.toString()}`);

  const ownedResolverSalt = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("owned-resolver"));
  const ownedResolverInitData = OwnedResolver.interface.encodeFunctionData("initialize", [deployer.address]);
  const ownedResolverAddress = await factory.callStatic.deployProxy(
    ownedResolverImplementation.address,
    ownedResolverSalt,
    ownedResolverInitData
  );
  await factory.deployProxy(ownedResolverImplementation.address, ownedResolverSalt, ownedResolverInitData);
  console.log("OwnedResolver deployed to:", ownedResolverAddress);

  const ownedResolver = await ethers.getContractAt("OwnedResolver", ownedResolverAddress);

  const setAddrOwnedTx = await ownedResolver.setAddr(namehashExampleEth, "0x1234567890123456789012345678901234567890");
  const setAddrOwnedReceipt = await setAddrOwnedTx.wait();
  console.log(`Gas used for setAddr with OwnedResolver: ${setAddrOwnedReceipt.gasUsed.toString()}`);

  const getAddrOwnedGas = await ethers.provider.estimateGas({
    to: ownedResolverAddress,
    data: ownedResolver.interface.encodeFunctionData("addr", [namehashExampleEth]),
  });
  console.log(`Gas used for addr with OwnedResolver: ${getAddrOwnedGas.toString()}`);

  const setAddrSavings = ((parseInt(setAddrOwnedReceipt.gasUsed.toString()) - parseInt(setAddrReceipt.gasUsed.toString())) / parseInt(setAddrOwnedReceipt.gasUsed.toString())) * 100;
  const getAddrCost = ((parseInt(getAddrGas.toString()) - parseInt(getAddrOwnedGas.toString())) / parseInt(getAddrOwnedGas.toString())) * 100;
  
  console.log(`\nRegistryAwareResolver uses ${setAddrSavings.toFixed(2)}% ${setAddrSavings > 0 ? "less" : "more"} gas for write operations (setAddr)`);
  console.log(`RegistryAwareResolver uses ${Math.abs(getAddrCost).toFixed(2)}% ${getAddrCost > 0 ? "more" : "less"} gas for read operations (addr)`);

  const envContent = `
DATASTORE_ADDRESS=${datastore.address}
ROOT_REGISTRY_ADDRESS=${rootRegistry.address}
ETH_REGISTRY_ADDRESS=${ethRegistry.address}
XYZ_REGISTRY_ADDRESS=${xyzRegistry.address}
EXAMPLE_REGISTRY_ADDRESS=${exampleRegistry.address}
FOO_REGISTRY_ADDRESS=${fooRegistry.address}
ETH_RESOLVER_ADDRESS=${ethResolverAddress}
XYZ_RESOLVER_ADDRESS=${xyzResolverAddress}
EXAMPLE_RESOLVER_ADDRESS=${exampleResolverAddress}
FOO_RESOLVER_ADDRESS=${fooResolverAddress}
OWNED_RESOLVER_ADDRESS=${ownedResolverAddress}
`;

  fs.writeFileSync(".env", envContent);
  console.log("\nDeployment addresses written to .env file");
}

try {
  await main();
  process.exit(0);
} catch (error) {
  console.error(error);
  process.exit(1);
}
