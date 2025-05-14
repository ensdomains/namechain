import hre from "hardhat";
import fs from "fs";
import dotenv from "dotenv";
import {
  namehash,
  keccak256,
  stringToBytes,
} from "viem";
dotenv.config();

async function main() {
  console.log("Listing names, resolvers, and ETH addresses...");

  const publicClient = await hre.viem.getPublicClient();
  const [walletClient] = await hre.viem.getWalletClients();
  console.log("Using account:", walletClient.account.address);

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

  const datastore = await hre.viem.getContractAt("RegistryDatastore", datastoreAddress);
  const rootRegistry = await hre.viem.getContractAt("RootRegistry", rootRegistryAddress);
  const ethRegistry = await hre.viem.getContractAt("PermissionedRegistry", ethRegistryAddress);
  const xyzRegistry = await hre.viem.getContractAt("PermissionedRegistry", xyzRegistryAddress);
  const exampleRegistry = await hre.viem.getContractAt("PermissionedRegistry", exampleRegistryAddress);
  const fooRegistry = await hre.viem.getContractAt("PermissionedRegistry", fooRegistryAddress);
  const ethResolver = await hre.viem.getContractAt("RegistryAwareResolver", ethResolverAddress);
  const xyzResolver = await hre.viem.getContractAt("RegistryAwareResolver", xyzResolverAddress);
  const exampleResolver = await hre.viem.getContractAt("RegistryAwareResolver", exampleResolverAddress);
  const fooResolver = await hre.viem.getContractAt("RegistryAwareResolver", fooResolverAddress);

  const namehashEth = namehash("eth");
  const namehashXyz = namehash("xyz");
  const namehashExampleEth = namehash("example.eth");
  const namehashExampleXyz = namehash("example.xyz");
  const namehashFooExampleEth = namehash("foo.example.eth");

  const ethAddress = await ethResolver.read.addr([namehashEth]);
  const xyzAddress = await xyzResolver.read.addr([namehashXyz]);
  const exampleEthAddress = await exampleResolver.read.addr([namehashExampleEth]);
  const exampleXyzAddress = await exampleResolver.read.addr([namehashExampleXyz]);
  const fooExampleEthAddress = await fooResolver.read.addr([namehashFooExampleEth]);

  const nameTable = [
    {
      name: "eth",
      resolver: ethResolverAddress,
      ethAddress: ethAddress,
      owner: walletClient.account.address,
    },
    {
      name: "xyz",
      resolver: xyzResolverAddress,
      ethAddress: xyzAddress,
      owner: walletClient.account.address,
    },
    {
      name: "example.eth",
      resolver: exampleResolverAddress,
      ethAddress: exampleEthAddress,
      owner: walletClient.account.address,
    },
    {
      name: "example.xyz",
      resolver: exampleResolverAddress,
      ethAddress: exampleXyzAddress,
      owner: walletClient.account.address,
    },
    {
      name: "foo.example.eth",
      resolver: fooResolverAddress,
      ethAddress: fooExampleEthAddress,
      owner: walletClient.account.address,
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

  const ethLabelHash = keccak256(stringToBytes(ethLabel));
  const xyzLabelHash = keccak256(stringToBytes(xyzLabel));
  const exampleLabelHash = keccak256(stringToBytes(exampleLabel));
  const fooLabelHash = keccak256(stringToBytes(fooLabel));

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
