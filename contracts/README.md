![Build status](https://github.com/ensdomains/namechain/actions/workflows/main.yml/badge.svg?branch=main)
[![Coverage Status](https://coveralls.io/repos/github/ensdomains/namechain/badge.svg?branch=main)](https://coveralls.io/github/ensdomains/namechain?branch=main)

# ENSv2 Contracts

Currently this repository hosts Proof-of-Concept contracts for ENSv2. See the [ENSv2 design doc](http://go.ens.xyz/ensv2) for details of the system architecture.

At present the following contracts are implemented:

- [RegistryDatastore](src/common/RegistryDatastore.sol) &mdash; an implementation of the registry datastore defined in the design doc. All registry contracts must use a singleton instance of the datastore for storage of subregistry and resolver addresses.
- [ERC1155Singleton](src/common/ERC1155Singleton.sol) &mdash; an implementation of the ERC1155 standard that permits only a single token per token ID. This saves on gas costs for storage while also permitting easy implementation of an `ownerOf` function.
- [PermissionedRegistry](src/common/PermissionedRegistry.sol) &mdash; an implementation of the v2 registry.
- [UniversalResolver](src/universalResolver/UniversalResolver.sol) &mdash; onchain ENSv2 resolution.
- [ETHFallbackResolver](src/L1/ETHFallbackResolver.sol) &mdash; crosschain resolver that combines mainnet v2 (ejected), mainnet v1 (unmigrated), and Namechain v2.

## Getting started

### Installation

1. Install foundry: [guide](https://book.getfoundry.sh/getting-started/installation)
2. Install [bun](https://bun.sh/)
3. Make sure to have the proper node.js version installed. See [/package.json#engines](../package.json#engines)
```sh
node --version
```

4. Install dependencies:

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

Testing is done using both Foundry and Hardhat.
Run all test suites:

```sh
bun run test         # ALL tests
```

Or run specific test suites:

```sh
bun run test:hardhat  # Run Hardhat tests
bun run test:forge    # Run Forge tests
bun run test:hardhat test/Ens.t.ts # specific Hardhat test
```

## Running the Devnet

There are two ways to run the devnet:

### Native Local Devnet (recommended)

Start a local devnet with L1 and L2 chains:

```sh
bun run devnet
```

This will start:

- L1 chain at http://localhost:8545 (Chain ID: 31337)
- L2 chain at http://localhost:8546 (Chain ID: 31338)

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

## Miscellaneous

Foundry also comes with cast, anvil, and chisel, all of which are useful for local development ([docs](https://book.getfoundry.sh/))

### Format

```shell
forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

## Publishing

Run `bun publish`. If there is a version bump, run `bun version <patch|minor|major>`.