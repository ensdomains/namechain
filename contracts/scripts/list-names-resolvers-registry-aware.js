import hre from "hardhat";
import fs from "fs";
import hardhat from "hardhat";
const { ethers } = hardhat;
import dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("Listing names, resolvers, and ETH addresses...");

  const [deployer] = await ethers.getSigners();
  console.log("Using account:", deployer.address);

  const datastoreAddress = process.env.DATASTORE_ADDRESS;
  const rootRegistryAddress = process.env.ROOT_REGISTRY_ADDRESS;
  const ethRegistryAddress = process.env.ETH_REGISTRY_ADDRESS;
  const xyzRegistryAddress = process.env.XYZ_REGISTRY_ADDRESS;
  const exampleRegistryAddress = process.env.EXAMPLE_REGISTRY_ADDRESS;
  const fooRegistryAddress = process.env.FOO_REGISTRY_ADDRESS;
  const ethResolverAddress = process.env.ETH_RESOLVER_ADDRESS;
  const xyzResolverAddress = process.env.XYZ_RESOLVER_ADDRESS;
  const exampleResolverAddress = process.env.EXAMPLE_RESOLVER_ADDRESS;
  const fooResolverAddress = process.env.FOO_RESOLVER_ADDRESS;

  const datastore = await ethers.getContractAt("RegistryDatastore", datastoreAddress);
  const rootRegistry = await ethers.getContractAt("RootRegistry", rootRegistryAddress);
  const ethRegistry = await ethers.getContractAt("PermissionedRegistry", ethRegistryAddress);
  const xyzRegistry = await ethers.getContractAt("PermissionedRegistry", xyzRegistryAddress);
  const exampleRegistry = await ethers.getContractAt("PermissionedRegistry", exampleRegistryAddress);
  const fooRegistry = await ethers.getContractAt("PermissionedRegistry", fooRegistryAddress);
  const ethResolver = await ethers.getContractAt("RegistryAwareResolver", ethResolverAddress);
  const xyzResolver = await ethers.getContractAt("RegistryAwareResolver", xyzResolverAddress);
  const exampleResolver = await ethers.getContractAt("RegistryAwareResolver", exampleResolverAddress);
  const fooResolver = await ethers.getContractAt("RegistryAwareResolver", fooResolverAddress);

  const namehashEth = ethers.utils.namehash("eth");
  const namehashXyz = ethers.utils.namehash("xyz");
  const namehashExampleEth = ethers.utils.namehash("example.eth");
  const namehashExampleXyz = ethers.utils.namehash("example.xyz");
  const namehashFooExampleEth = ethers.utils.namehash("foo.example.eth");

  const ethAddress = await ethResolver.addr(namehashEth);
  const xyzAddress = await xyzResolver.addr(namehashXyz);
  const exampleEthAddress = await exampleResolver.addr(namehashExampleEth);
  const exampleXyzAddress = await exampleResolver.addr(namehashExampleXyz);
  const fooExampleEthAddress = await fooResolver.addr(namehashFooExampleEth);

  const nameTable = [
    {
      name: "eth",
      resolver: ethResolverAddress,
      ethAddress: ethAddress,
      owner: deployer.address,
    },
    {
      name: "xyz",
      resolver: xyzResolverAddress,
      ethAddress: xyzAddress,
      owner: deployer.address,
    },
    {
      name: "example.eth",
      resolver: exampleResolverAddress,
      ethAddress: exampleEthAddress,
      owner: deployer.address,
    },
    {
      name: "example.xyz",
      resolver: exampleResolverAddress,
      ethAddress: exampleXyzAddress,
      owner: deployer.address,
    },
    {
      name: "foo.example.eth",
      resolver: fooResolverAddress,
      ethAddress: fooExampleEthAddress,
      owner: deployer.address,
    },
  ];

  console.table(nameTable);

  if (exampleEthAddress === exampleXyzAddress) {
    console.log("\nAliasing successful: example.eth and example.xyz resolve to the same address!");
    console.log(`Address: ${exampleEthAddress}`);
  } else {
    console.log("\nAliasing failed: example.eth and example.xyz resolve to different addresses.");
    console.log(`example.eth address: ${exampleEthAddress}`);
    console.log(`example.xyz address: ${exampleXyzAddress}`);
  }

  console.log("\nRegistry-Level Aliasing Explanation:");
  console.log("1. Both .eth and .xyz registries point to the same example subregistry");
  console.log("2. The example subregistry has a single resolver");
  console.log("3. When resolving example.eth or example.xyz, the system follows the registry hierarchy");
  console.log("4. Both paths lead to the same resolver and same address");
  console.log("5. No resolver-level aliasing is needed because the registry structure handles it");

  const ethLabel = "eth";
  const xyzLabel = "xyz";
  const exampleLabel = "example";
  const fooLabel = "foo";

  const ethLabelHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(ethLabel));
  const xyzLabelHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(xyzLabel));
  const exampleLabelHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(exampleLabel));
  const fooLabelHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(fooLabel));

  console.log("\nLabelhashes:");
  console.log(`eth: ${ethLabelHash}`);
  console.log(`xyz: ${xyzLabelHash}`);
  console.log(`example: ${exampleLabelHash}`);
  console.log(`foo: ${fooLabelHash}`);

  console.log("\nNamehashes:");
  console.log(`eth: ${namehashEth}`);
  console.log(`xyz: ${namehashXyz}`);
  console.log(`example.eth: ${namehashExampleEth}`);
  console.log(`example.xyz: ${namehashExampleXyz}`);
  console.log(`foo.example.eth: ${namehashFooExampleEth}`);

  console.log("\nRegistry Hierarchy:");
  console.log("RootRegistry");
  console.log("├── .eth Registry");
  console.log("│   └── example.eth Registry");
  console.log("│       └── foo.example.eth Registry");
  console.log("└── .xyz Registry");
  console.log("    └── example.xyz Registry (same as example.eth Registry)");
}

try {
  await main();
  process.exit(0);
} catch (error) {
  console.error(error);
  process.exit(1);
}
