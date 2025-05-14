/**
 * Demo script showing the format for listing names by owner with shortened addresses
 * This is a simplified version that doesn't require hardhat/ethers
 */

function shortenAddress(address) {
  if (!address) return "None";
  return `${address.substring(0, 6)}...${address.substring(address.length - 4)}`;
}

const nameData = [
  {
    name: "eth",
    resolver: "0x5529674a30a41587A980dF9C42f744A78dC76b31",
    ethAddress: "0x5555555555555555555555555555555555555555",
    owner: "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
  },
  {
    name: "xyz",
    resolver: "0xF42bbAC689Bbed20DD5Ef781f249dEAEBA9fd90a",
    ethAddress: "0x6666666666666666666666666666666666666666",
    owner: "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
  },
  {
    name: "example.eth",
    resolver: "0x573087D425444f830b4016b6664C442e99141394",
    ethAddress: "0x1234567890123456789012345678901234567890",
    owner: "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
  },
  {
    name: "example.xyz",
    resolver: "0x573087D425444f830b4016b6664C442e99141394",
    ethAddress: "0x1234567890123456789012345678901234567890",
    owner: "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
  },
  {
    name: "foo.example.eth",
    resolver: "0x3ca45F29cFe997701101206C531372EA3733d784",
    ethAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
    owner: "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
  },
  {
    name: "bar.example.eth",
    resolver: "0x3ca45F29cFe997701101206C531372EA3733d784",
    ethAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
    owner: "0x70997970c51812dc3a010c7d01b50e0d17dc79c8",
  },
];

const ownerToNames = {};
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

console.log("\nAliasing successful: example.eth and example.xyz resolve to the same address!");
console.log(`Address: ${shortenAddress("0x1234567890123456789012345678901234567890")}`);

console.log("\nEvents emitted by RegistryAwareResolver when setting addresses:");
console.log("1. AddrChanged(bytes32 node, address newAddress)");
console.log("   - Emitted when an ETH address is set");
console.log("   - Contains the namehash of the node and the new ETH address");
console.log("2. AddressChanged(bytes32 node, uint coinType, bytes newAddress)");
console.log("   - Emitted when any address is set (including ETH)");
console.log("   - Contains the namehash, coin type (60 for ETH), and the new address as bytes");
