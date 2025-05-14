import hre from "hardhat";
import fs from "fs";
import dotenv from "dotenv";
import {
  namehash,
  keccak256,
  stringToBytes,
} from "viem";
dotenv.config();

function shortenAddress(address) {
  if (!address) return "None";
  return `${address.substring(0, 6)}...${address.substring(address.length - 4)}`;
}

async function main() {
  console.log("Listing names by owner with resolvers and ETH addresses...");

  const publicClient = await hre.viem.getPublicClient();
  const [walletClient] = await hre.viem.getWalletClients();
  console.log("Using account:", shortenAddress(walletClient.account.address));

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

  const ownerToNames = {};

  const nameData = [
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

  nameData.forEach(data => {
    const owner = data.owner;
    if (!ownerToNames[owner]) {
      ownerToNames[owner] = [];
    }
    ownerToNames[owner].push({
      name: data.name,
      resolver: shortenAddress(data.resolver),
      ethAddress: shortenAddress(data.ethAddress)
    });
  });

  console.log("\nNames grouped by owner:");
  for (const owner in ownerToNames) {
    console.log(`\nOwner: ${shortenAddress(owner)}`);
    console.table(ownerToNames[owner]);
  }

  if (exampleEthAddress === exampleXyzAddress) {
    console.log("\nAliasing successful: example.eth and example.xyz resolve to the same address!");
    console.log(`Address: ${shortenAddress(exampleEthAddress)}`);
  } else {
    console.log("\nAliasing failed: example.eth and example.xyz resolve to different addresses.");
    console.log(`example.eth address: ${shortenAddress(exampleEthAddress)}`);
    console.log(`example.xyz address: ${shortenAddress(exampleXyzAddress)}`);
  }

  console.log("\nEvents emitted by RegistryAwareResolver when setting addresses:");
  console.log("1. AddrChanged(bytes32 node, address newAddress)");
  console.log("   - Emitted when an ETH address is set");
  console.log("   - Contains the namehash of the node and the new ETH address");
  console.log("2. AddressChanged(bytes32 node, uint coinType, bytes newAddress)");
  console.log("   - Emitted when any address is set (including ETH)");
  console.log("   - Contains the namehash, coin type (60 for ETH), and the new address as bytes");

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
