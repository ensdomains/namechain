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

1. Install [Foundry](https://book.getfoundry.sh/getting-started/installation)
1. Install [bun](https://bun.sh/)
1. `bun i`

### Build

```sh
forge build
```

### Test

Testing is done using both Foundry and Hardhat.

```sh
bun run test         # ALL tests
forge test           # Foundry tests
bun run test:hardhat # Hardhat tests
bun run test:hardhat test/Ens.t.ts # specific Hardhat test
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
