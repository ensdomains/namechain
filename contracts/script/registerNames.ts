import { createPublicClient, http, type Chain, type PublicClient, getContract, type Log, decodeEventLog, type Abi, type DecodeEventLogReturnType, encodeFunctionData, parseEventLogs, encodeAbiParameters, parseAbiParameters } from "viem";
import { readFileSync } from "fs";
import { join } from "path";
import { privateKeyToAccount, mnemonicToAccount } from "viem/accounts";

// Define chain types
const l1Chain: Chain = {
  id: 31337,
  name: "Local L1",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: ["http://127.0.0.1:8545"] },
    public: { http: ["http://127.0.0.1:8545"] },
  },
};

const l2Chain: Chain = {
  id: 31338,
  name: "Local L2",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: ["http://127.0.0.1:8546"] },
    public: { http: ["http://127.0.0.1:8546"] },
  },
};

// Connect to the networks
const l1Client = createPublicClient({
  chain: l1Chain,
  transport: http(),
});

const l2Client = createPublicClient({
  chain: l2Chain,
  transport: http(),
});

// Read deployment files
const rootRegistryPath = join(process.cwd(), "deployments", "l1-local", "RootRegistry.json");
const l1EthRegistryPath = join(process.cwd(), "deployments", "l1-local", "L1ETHRegistry.json");
const ethRegistryPath = join(process.cwd(), "deployments", "l2-local", "ETHRegistry.json");
const l1VerifiableFactoryPath = join(process.cwd(), "deployments", "l1-local", "VerifiableFactory.json");
const l1DedicatedResolverImplPath = join(process.cwd(), "deployments", "l1-local", "DedicatedResolverImpl.json");
const l2VerifiableFactoryPath = join(process.cwd(), "deployments", "l2-local", "VerifiableFactory.json");
const l2DedicatedResolverImplPath = join(process.cwd(), "deployments", "l2-local", "DedicatedResolverImpl.json");
const userRegistryImplPath = join(process.cwd(), "deployments", "l2-local", "UserRegistryImpl.json");
const registryDatastorePath = join(process.cwd(), "deployments", "l2-local", "RegistryDatastore.json");
const registryMetadataPath = join(process.cwd(), "deployments", "l2-local", "SimpleRegistryMetadata.json");
const l1EjectionControllerPath = join(process.cwd(), "deployments", "l1-local", "L1EjectionController.json");
const l2EjectionControllerPath = join(process.cwd(), "deployments", "l2-local", "L2EjectionController.json");

const rootRegistryDeployment = JSON.parse(readFileSync(rootRegistryPath, "utf8"));
const l1EthRegistryDeployment = JSON.parse(readFileSync(l1EthRegistryPath, "utf8"));
const ethRegistryDeployment = JSON.parse(readFileSync(ethRegistryPath, "utf8"));
const l1VerifiableFactoryDeployment = JSON.parse(readFileSync(l1VerifiableFactoryPath, "utf8"));
const l1dedicatedResolverImplDeployment = JSON.parse(readFileSync(l1DedicatedResolverImplPath, "utf8"));
const l2VerifiableFactoryDeployment = JSON.parse(readFileSync(l2VerifiableFactoryPath, "utf8"));
const l2dedicatedResolverImplDeployment = JSON.parse(readFileSync(l2DedicatedResolverImplPath, "utf8"));
const userRegistryImplDeployment = JSON.parse(readFileSync(userRegistryImplPath, "utf8"));
const registryDatastoreDeployment = JSON.parse(readFileSync(registryDatastorePath, "utf8"));
const registryMetadataDeployment = JSON.parse(readFileSync(registryMetadataPath, "utf8"));
const l1EjectionControllerDeployment = JSON.parse(readFileSync(l1EjectionControllerPath, "utf8"));
const l2EjectionControllerDeployment = JSON.parse(readFileSync(l2EjectionControllerPath, "utf8"));

const resolverAddresses = new Set<string>();

async function waitForTransaction(hash: `0x${string}`, client: PublicClient) {
  return await client.waitForTransactionReceipt({ hash });
}

function decodeEvent(log: Log, abi: Abi) {

  try {
    return decodeEventLog({
      abi,
      data: log.data,
      topics: log.topics,
    });
  } catch (error) {
    return null;
  }
}

function formatEventLog(log: Log, abi: Abi) {
  const decoded = decodeEvent(log, abi);
  if (!decoded) {
    return {
      eventName: "Unknown Event",
      args: "Failed to decode event data",
    };
  }

  return {
    eventName: decoded.eventName,
    args: decoded.args,
  };
}

async function deployDedicatedResolver(name: string, owner: `0x${string}`, account: any, chain: string) {
  let verifiableFactoryDeployment;
  let dedicatedResolverImplDeployment;
  let client;
  if(chain === "l1"){
    verifiableFactoryDeployment = l1VerifiableFactoryDeployment;
    dedicatedResolverImplDeployment = l1dedicatedResolverImplDeployment;
    client = l1Client;
  }else{
    verifiableFactoryDeployment = l2VerifiableFactoryDeployment;
    dedicatedResolverImplDeployment = l2dedicatedResolverImplDeployment;
    client = l2Client;
  }
  const verifiableFactory = getContract({
    address: verifiableFactoryDeployment.address,
    abi: verifiableFactoryDeployment.abi,
    client: client,
  });

  const salt = BigInt(Date.now());
  const initData = encodeFunctionData({
    abi: dedicatedResolverImplDeployment.abi,
    functionName: "initialize",
    args: [owner],
  });

  const hash = await verifiableFactory.write.deployProxy(
    [dedicatedResolverImplDeployment.address, salt, initData],
    { account }
  );
  console.log("***1", hash);
  // Wait for the transaction to be mined
  const receipt = await waitForTransaction(hash, client);
  console.log("***2", receipt);
  const logs = parseEventLogs({
    abi: verifiableFactoryDeployment.abi,
    eventName: "ProxyDeployed",
    logs: receipt.logs,
  }) as unknown as [{ args: { proxyAddress: `0x${string}` } }];
  console.log("***3", logs);
  if (!logs.length) {
    throw new Error("No ProxyDeployed event found");
  }
  console.log("***4", logs[0].args.proxyAddress);
  return logs[0].args.proxyAddress;
}

async function deployUserRegistry(name: string, owner: `0x${string}`, account: any) {
  const verifiableFactory = getContract({
    address: l2VerifiableFactoryDeployment.address,
    abi: l2VerifiableFactoryDeployment.abi,
    client: l2Client,
  });

  const salt = BigInt(Date.now());
  const initData = encodeFunctionData({
    abi: userRegistryImplDeployment.abi,
    functionName: "initialize",
    args: [
      registryDatastoreDeployment.address,
      registryMetadataDeployment.address,
      0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffn, // All roles
      owner
    ],
  });

  const hash = await verifiableFactory.write.deployProxy(
    [userRegistryImplDeployment.address, salt, initData],
    { account }
  );

  // Wait for the transaction to be mined
  const receipt = await waitForTransaction(hash, l2Client);
  const logs = parseEventLogs({
    abi: l2VerifiableFactoryDeployment.abi,
    eventName: "ProxyDeployed",
    logs: receipt.logs,
  }) as unknown as [{ args: { proxyAddress: `0x${string}` } }];

  if (!logs.length) {
    throw new Error("No ProxyDeployed event found");
  }

  return logs[0].args.proxyAddress;
}

async function registerNames() {
  // Create an account from the default mnemonic
  const account = mnemonicToAccount("test test test test test test test test test test test junk");

  // Get the L2 registry
  const ethRegistry = getContract({
    address: ethRegistryDeployment.address,
    abi: ethRegistryDeployment.abi,
    client: l2Client,
  });

  // Define the names to register
  const names = ["test1", "test2", "test3", "ejected"];
  
  // Store UserRegistry addresses for aliasing
  const userRegistryAddresses = new Map<string, string>();
  
  // Register names on L2
  console.log("Registering names on L2...");
  for (const name of names) {
    // Deploy a DedicatedResolver for this name
    console.log(`Deploying DedicatedResolver for ${name}...`);
    const resolverAddress = await deployDedicatedResolver(name, account.address, account, "l2");
    console.log(`DedicatedResolver deployed at ${resolverAddress}`);

    // Deploy a UserRegistry for this name
    console.log(`Deploying UserRegistry for ${name}...`);
    const userRegistryAddress = await deployUserRegistry(name, account.address, account);
    console.log(`UserRegistry deployed at ${userRegistryAddress}`);
    userRegistryAddresses.set(name, userRegistryAddress);

    const userRegistry = getContract({
      address: userRegistryAddress,
      abi: userRegistryImplDeployment.abi,
      client: l2Client,
    });

    // Set the ETH address in the resolver
    const dedicatedResolver = getContract({
      address: resolverAddress,
      abi: l2dedicatedResolverImplDeployment.abi,
      client: l2Client,
    });

    // Register names
    console.log(`Registering ${name}...`);
    const tx = await ethRegistry.write.register(
      [
        name,
        account.address,
        userRegistryAddress,
        dedicatedResolver.address,
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffn, // All roles
        0xffffffffffffffffn, // MAX_EXPIRY
      ],
      { account }
    );
    await waitForTransaction(tx, l2Client);

    console.log(`Transaction hash: ${tx}`);
    const result = await ethRegistry.read.getNameData([name]) as [bigint, bigint, number];
    const [tokenId, expiry, tokenIdVersion] = result;

    console.log(`Setting ETH address for ${name}...`);
    await dedicatedResolver.write.setAddr(
      [60n, account.address],
      { account }
    );
    console.log(`Setting TEXT record for ${name}...`);
    await dedicatedResolver.write.setText(
      ["domain", name],
      { account }
    );

    console.log(`Token ID: ${tokenId}`);
    console.log(`Expiry: ${expiry}`);
    console.log(`Token ID Version: ${tokenIdVersion}`);

    // For ejected.eth, transfer to L2EjectionController
    if (name === "ejected") {
      console.log("\nPreparing to eject ejected.eth...");
      const l2nameData = await ethRegistry.read.getNameData([name]) as { tokenId: bigint };
      console.log("***l2nameData", l2nameData);
      // Get L1 registry and controller addresses
      const l1EthRegistry = getContract({
        address: l1EthRegistryDeployment.address,
        abi: l1EthRegistryDeployment.abi,
        client: l1Client,
      });

      const l2EjectionController = getContract({
        address: l2EjectionControllerDeployment.address,
        abi: l2EjectionControllerDeployment.abi,
        client: l2Client,
      });


      // Deploy L1 Dedicated Resolver for ejected.eth
      console.log("\nDeploying L1 Dedicated Resolver for ejected.eth...");
      const l1ResolverAddress = await deployDedicatedResolver(name, account.address, account, "l1");
      console.log("***3", l1ResolverAddress);

      console.log(`L1 Dedicated Resolver deployed at ${l1ResolverAddress}`);
      

      // Prepare transfer data
      const transferDataParameters = [
        name,
        account.address, // L1 owner
        l1EthRegistry.address, // L1 subregistry
        l1ResolverAddress, // L1 resolver
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffn, // All roles
        0xffffffffffffffffn, // MAX_EXPIRY
      ] as const;
      console.log("***transferDataParameters", transferDataParameters);
      const encodedData = encodeAbiParameters(
        parseAbiParameters("(string,address,address,address,uint256,uint64)"),
        [transferDataParameters],
      );

      console.log("Transferring ejected.eth to L2EjectionController...");
      const transferTx = await ethRegistry.write.safeTransferFrom(
        [
          account.address,
          l2EjectionController.address,
          tokenId,
          1n,
          encodedData,
        ],
        { account }
      );
      await waitForTransaction(transferTx, l2Client);
      console.log(`Token transferred to L2EjectionController, tx hash: ${transferTx}`);

      // Verify the transfer
      const newOwner = await l1EthRegistry.read.ownerOf([tokenId]);
      console.log(`New owner on L1: ${newOwner}`);
      console.log("✓ Name successfully ejected to L1");
      
      // Set records in the L1 resolver
      const l1Resolver = getContract({
        address: l1ResolverAddress,
        abi: l1dedicatedResolverImplDeployment.abi,
        client: l1Client,
      });

      console.log("Setting ETH address for ejected.eth on L1...");
      const nonce = await l1Client.getTransactionCount({ address: account.address });
      const setAddrTx = await l1Resolver.write.setAddr(
        [60n, account.address],
        { account, nonce:nonce + 1 }
      );
      await waitForTransaction(setAddrTx, l1Client);
      console.log("Setting TEXT record for ejected.eth on L1...");
      const setTextTx = await l1Resolver.write.setText(
        ["domain", "ejected on l1"],
        { account, nonce:nonce + 2 }
      );
      await waitForTransaction(setTextTx, l1Client);
      console.log("✓ L1 records set successfully");
    }

    // For test1, create the subdomain structure
    if (name === "test1") {
      const subname = 'a';
      console.log(`Deploying subname DedicatedResolver for ${subname}.${name}...`);
      const subnameResolverAddress = await deployDedicatedResolver(subname, account.address, account, "l");
      console.log(`DedicatedResolver deployed at ${subnameResolverAddress}`);

      // Deploy a UserRegistry for a.test1
      console.log(`Deploying UserRegistry for ${subname}.${name}...`);
      const subnameUserRegistryAddress = await deployUserRegistry(`${subname}.${name}`, account.address, account);
      console.log(`UserRegistry deployed at ${subnameUserRegistryAddress}`);
      userRegistryAddresses.set(`${subname}.${name}`, subnameUserRegistryAddress);

      const subnameUserRegistry = getContract({
        address: subnameUserRegistryAddress,
        abi: userRegistryImplDeployment.abi,
        client: l2Client,
      });

      // Set the ETH address in the resolver
      const subnameDedicatedResolver = getContract({
        address: subnameResolverAddress,
        abi: l2dedicatedResolverImplDeployment.abi,
        client: l2Client,
      });

      // Create subname 'a.test1.eth'
      console.log(`Creating subname a.${name}.eth... with ${subnameDedicatedResolver.address}`);
      const subnameTx = await userRegistry.write.register(
        [
          subname,
          account.address,
          subnameUserRegistryAddress,
          subnameDedicatedResolver.address,
          0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffn, // All roles
          0xffffffffffffffffn, // MAX_EXPIRY
        ],
        { account }
      );
      await waitForTransaction(subnameTx, l2Client);

      // Set records for a.test1.eth
      console.log(`Setting ETH address for ${subname}.${name}...`);
      await subnameDedicatedResolver.write.setAddr(
        [60n, account.address],
        { account }
      );
      console.log(`Setting TEXT record for ${subname}.${name}...`);
      await subnameDedicatedResolver.write.setText(
        ["subdomain", `a.${name}`],
        { account }
      );

      // Create aa.a.test1.eth
      const subsubname = 'aa';
      console.log(`Deploying subname DedicatedResolver for ${subsubname}.${subname}.${name}...`);
      const subsubnameResolverAddress = await deployDedicatedResolver(subsubname, account.address, account, "l2");
      console.log(`DedicatedResolver deployed at ${subsubnameResolverAddress}`);

      // Deploy a UserRegistry for aa.a.test1
      console.log(`Deploying UserRegistry for ${subsubname}.${subname}.${name}...`);
      const subsubnameUserRegistryAddress = await deployUserRegistry(`${subsubname}.${subname}.${name}`, account.address, account);
      console.log(`UserRegistry deployed at ${subsubnameUserRegistryAddress}`);

      const subsubnameUserRegistry = getContract({
        address: subsubnameUserRegistryAddress,
        abi: userRegistryImplDeployment.abi,
        client: l2Client,
      });

      // Set the ETH address in the resolver
      const subsubnameDedicatedResolver = getContract({
        address: subsubnameResolverAddress,
        abi: l2dedicatedResolverImplDeployment.abi,
        client: l2Client,
      });

      // Create subname 'aa.a.test1.eth'
      console.log(`Creating subname aa.${subname}.${name}.eth... with ${subsubnameDedicatedResolver.address}`);
      const subsubnameTx = await subnameUserRegistry.write.register(
        [
          subsubname,
          account.address,
          subsubnameUserRegistryAddress,
          subsubnameDedicatedResolver.address,
          0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffn, // All roles
          0xffffffffffffffffn, // MAX_EXPIRY
        ],
        { account }
      );
      await waitForTransaction(subsubnameTx, l2Client);

      // Set records for aa.a.test1.eth
      console.log(`Setting ETH address for ${subsubname}.${subname}.${name}...`);
      await subsubnameDedicatedResolver.write.setAddr(
        [60n, account.address],
        { account }
      );
      console.log(`Setting TEXT record for ${subsubname}.${subname}.${name}...`);
      await subsubnameDedicatedResolver.write.setText(
        ["subsubdomain", `${subsubname}.${subname}.${name}`],
        { account }
      );
    }
  }

  // Create alias for a.test2.eth by setting its subregistry to a.test1.eth's UserRegistry
  if (userRegistryAddresses.has("test2") && userRegistryAddresses.has("a.test1")) {
    const test2UserRegistry = getContract({
      address: userRegistryAddresses.get("test2")!,
      abi: userRegistryImplDeployment.abi,
      client: l2Client,
    });

    console.log("\nCreating alias for a.test2.eth...");
    const aliasTx = await test2UserRegistry.write.register(
      [
        "a",
        account.address,
        userRegistryAddresses.get("a.test1")!, // Use a.test1.eth's UserRegistry
        "0x0000000000000000000000000000000000000000" as `0x${string}`, // No dedicated resolver needed for alias
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffn, // All roles
        0xffffffffffffffffn, // MAX_EXPIRY
      ],
      { account }
    );
    await waitForTransaction(aliasTx, l2Client);
    console.log("Alias created successfully!");
  }

  console.log("\nAll Resolver Addresses Set via ResolverUpdate:");
  console.log("----------------");
  if (resolverAddresses.size === 0) {
    console.log("No resolver addresses found.");
  } else {
    resolverAddresses.forEach(resolver => {
      console.log(`- ${resolver}`);
    });
  }
  console.log("----------------");
  console.log(`Total unique resolver addresses: ${resolverAddresses.size}`);
}

registerNames();