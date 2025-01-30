# ENSv2 Contracts

Currently this repository hosts Proof-of-Concept contracts for ENSv2. See the [ENSv2 design doc](http://go.ens.xyz/ensv2) for details of the system architecture.

At present the following contracts are implemented:
 - [RegistryDatastore](src/registry/RegistryDatastore.sol) - an implementation of the registry datastore defined in the design doc. All registry contracts must use a singleton instance of the datastore for storage of subregistry and resolver addresses.
 - [ERC1155Singleton](src/registry/ERC1155Singleton.sol) - an implementation of the ERC1155 standard that permits only a single token per token ID. This saves on gas costs for storage while also permitting easy implementation of an `ownerOf` function.
 - [BaseRegistry](src/registry/BaseRegistry.sol) - an implementation of the registry defined in the design doc, to be used as a base class for custom implementations.
 - [RootRegistry](src/registry/RootRegistry.sol) - an implementation of an ENSv2 registry to be used as the root of the name hierarchy. Owned by a single admin account that can authorise others to create and update TLDs. Supports locking TLDs so they cannot be further modified.
 - [ETHRegistry](src/registry/ETHRegistry.sol) - a basic implementation of an ENSv2 .eth registry. Supports locking TLDs and name expirations; when a name is expired, its resolver and subregistry addresses are zeroed out. User registrations and renewals are expected to occur via a controller contract that handles payments etc, just as in ENSv1.
 - [UserRegistry](src/registry/UserRegistry.sol) - a sample implementation of a standardized user registry contract. Supports locking subnames.
 - [UniversalResolver](src/utils/UniversalResolver.sol) - a sample implementation of the ENSv2 resolution algorithm.

The ENSv2 contracts module uses forge + hardhat combined to allow for simple unit testing, e2e tests (incl. CCIP-Read support), performant build forks, etc.

## Foundry (forge) installation

https://book.getfoundry.sh/getting-started/installation

## Getting started

### Installation

Install foundry: [guide](https://book.getfoundry.sh/getting-started/installation)

Install packages (bun)

```sh
bun install
```

### Build

```sh
forge build
```

### Test

Testing is done in both forge and hardhat, so you can use the helper script.

```sh
bun run test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Miscellaneous

Foundry also comes with cast, anvil, and chisel, all of which are useful for local development ([docs](https://book.getfoundry.sh/))

## Usage Examples

### Register a name using ETHRegistry

You can use the Hardhat console to interact with the deployed contracts:

```typescript
// Start the Hardhat console
$ bun run console --network local

// Import utility functions
const utils = await import('./test/utils/utils.ts')
const { labelhashUint256 } = utils

// Get contract instance
const ETHRegistry = await ethers.getContractFactory("ETHRegistry")
const ethRegistry = await ETHRegistry.attach("YOUR_DEPLOYED_ETH_REGISTRY_ADDRESS")

// Get signer's address
const signer = await ethers.provider.getSigner()
const signerAddress = signer.address

// First, ensure the signer has the REGISTRAR_ROLE
const REGISTRAR_ROLE = await ethRegistry.REGISTRAR_ROLE()
await ethRegistry.grantRole(REGISTRAR_ROLE, signerAddress)

// Register the name
// register(string label, address owner, IRegistry registry, uint96 flags, uint64 expires)
const name = 'test'
const expires = Math.floor(Date.now() / 1000) + 31536000 // 1 year from now
const tx = await ethRegistry.register(
    name,                // label
    signerAddress,       // owner
    ethRegistry.target,  // registry (using ETHRegistry itself as subregistry)
    0,                   // flags
    expires             // expiration timestamp
)
await tx.wait()

// Verify the registration
const labelHash = labelhashUint256(name)
const owner = await ethRegistry.ownerOf(labelHash)
console.log(`Owner of '${name}.eth': ${owner}`)

// Optional: Set a resolver
const tx2 = await ethRegistry.setResolver(labelHash, "RESOLVER_ADDRESS")
await tx2.wait()

// If using PublicResolver, you can set records:
const PublicResolver = await ethers.getContractFactory("PublicResolver")
const resolver = await PublicResolver.attach("RESOLVER_ADDRESS")

// Set an address record
const tx3 = await resolver.setAddr(labelHash, signerAddress)
await tx3.wait()

// Set a text record
const tx4 = await resolver.setText(labelHash, "email", "your@email.com")
await tx4.wait()
```

Common labelhashes for reference:
```typescript
labelhashUint256('eth')    // 35894389512221139346028120028875095598761990588366713962827482865185691260912n
labelhashUint256('test')   // 70622639689279718371527342103894932928233838121221666359043189029713682937432n
```
