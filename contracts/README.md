![Build status](https://github.com/ensdomains/namechain/actions/workflows/main.yml/badge.svg?branch=main)
[![Coverage Status](https://coveralls.io/repos/github/ensdomains/namechain/badge.svg?branch=main)](https://coveralls.io/github/ensdomains/namechain?branch=main)

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

1. Install foundry: [guide](https://book.getfoundry.sh/getting-started/installation)
2. Install dependencies:

```sh
bun i
cd contracts
forge i
```

### Build

```sh
forge build
```

### Test

Run all test suites:

```sh
bun run test
```

Or run specific test suites:

```sh
bun run test:hardhat  # Run Hardhat tests
bun run test:forge    # Run Forge tests
```

## Running the Devnet

There are two ways to run the devnet:

### Using Docker Compose

1. Make sure you have Docker and Docker Compose installed
2. Run the devnet using either:

   ```bash
   # Using local build
   docker compose up -d

   # Or using pre-built image from GitHub Container Registry
   docker pull ghcr.io/ensdomains/namechain:latest
   docker compose up -d
   ```

3. The devnet will be available at:
   - L1 Chain: http://localhost:8545 (Chain ID: 31337)
   - L2 Chain: http://localhost:8546 (Chain ID: 31338)

To view logs:

```bash
docker logs -f namechain-devnet-1
```

To stop the devnet:

```bash
docker compose down
```

### Local Development

### Run Local Devnet

Start a local devnet with L1 and L2 chains:

```sh
bun run devnet
```

This will start:

- L1 chain at http://localhost:8545 (Chain ID: 31337)
- L2 chain at http://localhost:8546 (Chain ID: 31338)

### Format

```shell
forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Miscellaneous

Foundry also comes with cast, anvil, and chisel, all of which are useful for local development ([docs](https://book.getfoundry.sh/))
