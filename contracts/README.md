![Build status](https://github.com/ensdomains/namechain/actions/workflows/main.yml/badge.svg?branch=main)
[![Coverage Status](https://coveralls.io/repos/github/ensdomains/namechain/badge.svg?branch=main)](https://coveralls.io/github/ensdomains/namechain?branch=main)

# ENSv2 Contracts

This repository hosts the smart contracts for ENSv2 (Ethereum Name Service version 2), a next-generation naming system designed for scalability and cross-chain functionality. For comprehensive architectural details, see the [ENSv2 design doc](http://go.ens.xyz/ensv2).

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
  - [Core Concepts](#core-concepts)
  - [Token ID System](#token-id-system)
  - [Access Control](#access-control)
- [Contract Documentation](#contract-documentation)
  - [Registry System](#registry-system)
  - [L2 Components](#l2-components)
  - [L1 Components](#l1-components)
  - [Cross-Chain Bridge](#cross-chain-bridge)
  - [Resolution](#resolution)
- [Getting started](#getting-started)
- [Running the Devnet](#running-the-devnet)
- [Miscellaneous](#miscellaneous)

## Overview

ENSv2 transitions from a flat registry to a hierarchical system that enables:

- **L2 Scalability**: .eth names registered and managed on Layer 2 with reduced gas costs
- **Flexible Ownership**: Custom registry implementations for different ownership models
- **Cross-Chain Support**: Seamless name resolution across L1 and L2
- **Backward Compatibility**: Unmigrated ENSv1 names continue to function
- **Enhanced Security**: Names can be "ejected" to L1 for maximum security guarantees

### Key Features

1. **Hierarchical Registries**: Each name has its own registry contract managing its subdomains
2. **Canonical ID System**: Canonical internal token ID enables for external token ID to be changed but still map to the same internal data
3. **Role-Based Access Control**: Gas-efficient access control supporting up to 32 roles
4. **Universal Resolver**: Single entry point for all name resolution
5. **Migration Framework**: Transition path from ENSv1 to ENSv2

## Architecture

### Core Concepts

**Registries**
- Each registry is responsible for one name and its direct subdomains
- Registries implement ERC1155, treating subdomains as NFTs
- Must implement the `IRegistry` interface for standard resolution
- All registries store data in the singleton `RegistryDatastore` to reduce the number of storage proofs needed for CCIP-Read cross-chain lookups

**Root Registry** → **TLD Registries** (.eth, .box, etc.) → **Domain Registries** (example.eth) → **Subdomain Registries** (sub.example.eth)

**Resolution Process**
1. Start at root registry
2. Recursively traverse to find the deepest registry with a resolver set
3. Query that resolver for the requested record
4. Supports wildcard resolution (parent resolver handles subdomains)

### Mutable Token ID System

Token IDs regenerate on significant state changes (expiry, permission updates) to prevent griefing attacks from expired token approvals. There is an internal id called canonical ID that points to the same storage.

#### Key Properties

1. **Token ID** (`uint256`): External id representing a name
   - Different tokenIds can exist for the same name (e.g., after expiry/re-registration)
   - Lower 32 bits may encode version, timestamp, or other metadata

2. **Canonical ID** (`uint256`): Internal stable storage key derived from token ID
   - Always has lower 32 bits zeroed out
   - Formula: `canonicalId = tokenId ^ uint32(tokenId)

#### Token ID Changes

Token IDs change in two scenarios:

1. **Access Control Changes**: When permissions are modified, the token ID regenerates to prevent griefing attacks:
   - **Attack Scenario**: Owner lists name for sale on marketplace, then changes permissions before sale completes
   - **Protection**: New token ID invalidates the marketplace listing, preventing buyer from receiving name with unexpected permissions

2. **Name Expiry**: When a name expires and is re-registered, it receives a new token ID

#### Which Functions Use Which ID?

**Token ID** is used for:
- **ERC1155 operations**: `ownerOf()`, `safeTransferFrom()`, `balanceOf()`
- **Permission checks**: Access control validates against token ID
- **Public-facing operations**: `setResolver(tokenId, ...)`, `setSubregistry(tokenId, ...)`
- **Events**: All events emit the current token ID

**Canonical ID** is used internally for:
- **Storage lookups**: `DATASTORE.getEntry(registry, canonicalId)`
- **Storage writes**: `DATASTORE.setEntry(registry, canonicalId, entry)`

```solidity
// Example: setResolver() uses both
function setResolver(uint256 tokenId, address resolver) external {
    // 1. Check permissions using tokenId
    _checkRoles(tokenId, ROLE_SET_RESOLVER, msg.sender);

    // 2. Store using canonical ID
    uint256 canonicalId = LibLabel.getCanonicalId(tokenId);
    DATASTORE.setResolver(canonicalId, resolver);

    // 3. Emit event with tokenId
    emit ResolverUpdate(tokenId, resolver);
}
```

### Access Control

ENSv2 uses **Enhanced Access Control (EAC)**, a role-based access control system that stores up to 32 roles and their assignee counts in a single uint256:

Eeach role have a complementary admin role that grants the holder permission to grant/revoke that role. Roles are assigned against a "resource", which is just a uint256 that can represent anything. For a given role assigned for a given resource, a maximum of 15 assignees are allowed. For registered names the canonical token ID acts as the equivalent access control resource id.

#### Role Representation

```
Role Bitmap (uint256):
┌────────── 128 bits ───────────┬────────── 128 bits ───────────┐
│     Admin Roles (32-63)       │     Regular Roles (0-31)      │
│  Each role = 4 bits (nybble)  │  Each role = 4 bits (nybble)  │
└───────────────────────────────┴───────────────────────────────┘
```

Each 4-bit nybble stores the **assignee count** (max 15) for that role.

#### Key Features

1. **Resource-Based Permissions**: Roles are scoped to specific resources (e.g., tokenIds)
   ```solidity
   // Grant role for specific token
   registry.grantRoles(tokenId, ROLE_SET_RESOLVER, alice);

   // Check permission
   registry.checkRoles(tokenId, ROLE_SET_RESOLVER, alice);
   ```

2. **Root Resource Override**: Roles in `ROOT_RESOURCE` (0x0) apply globally
   ```solidity
   // Grant admin powers across all names
   registry.grantRoles(ROOT_RESOURCE, ROLE_OWNER, admin);
   ```

3. **Role Composition**: Combine roles using bitwise OR
   ```solidity
   uint256 roles = ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY | ROLE_CAN_TRANSFER;
   registry.grantRoles(tokenId, roles, operator);
   ```

4. **Admin Roles**: Each role has a corresponding admin that can grant/revoke it
   ```solidity
   // Role 0's admin is role 32
   // Role 1's admin is role 33, etc.
   uint256 adminRole = regularRole + 32;
   ```

#### Registry Roles

From [`RegistryRolesLib.sol`](src/common/registry/libraries/RegistryRolesLib.sol):

| Role | Bit Position | Description |
|------|--------------|-------------|
| `ROLE_OWNER` | 0 | Full control over the name |
| `ROLE_SET_RESOLVER` | 1 | Can change the resolver address |
| `ROLE_SET_RESOLVER_ADMIN` | 2 | Can grant/revoke ROLE_SET_RESOLVER |
| `ROLE_SET_SUBREGISTRY` | 3 | Can change subregistry addresses |
| `ROLE_SET_SUBREGISTRY_ADMIN` | 4 | Can grant/revoke ROLE_SET_SUBREGISTRY |
| `ROLE_CAN_TRANSFER` | 5 | Can transfer name ownership |
| `ROLE_CAN_TRANSFER_ADMIN` | 6 | Can grant/revoke ROLE_CAN_TRANSFER |
| `ROLE_CAN_BURN` | 7 | Can burn (delete) the name |
| `ROLE_CAN_BURN_ADMIN` | 8 | Can grant/revoke ROLE_CAN_BURN |

#### Example Usage

```solidity
import {RegistryRolesLib} from "./libraries/RegistryRolesLib.sol";

// Scenario: Delegate resolver management without transfer rights
uint256 tokenId = LibLabel.labelToCanonicalId("example");

// Grant only resolver permissions
registry.grantRoles(
    tokenId,
    RegistryRolesLib.ROLE_SET_RESOLVER,
    resolverManager
);

// Grant multiple roles at once
uint256 operatorRoles = RegistryRolesLib.ROLE_SET_RESOLVER |
                        RegistryRolesLib.ROLE_SET_SUBREGISTRY;
registry.grantRoles(tokenId, operatorRoles, operator);

// Check if user has required permissions
bool canSetResolver = registry.hasRoles(
    tokenId,
    RegistryRolesLib.ROLE_SET_RESOLVER,
    user
);

// Admin can grant roles to others
registry.grantRoles(
    tokenId,
    RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN,
    admin
);
```

## Contract Documentation

### Registry System

#### `IRegistry` - Core Interface
[src/common/registry/interfaces/IRegistry.sol](src/common/registry/interfaces/IRegistry.sol)

Standard interface all registries must implement:
```solidity
interface IRegistry is IERC1155Singleton {
    event NewSubname(uint256 indexed labelHash, string label);

    function getSubregistry(string calldata label) external view returns (IRegistry);
    function getResolver(string calldata label) external view returns (address);
}
```

#### `RegistryDatastore` - Singleton Storage
[src/common/RegistryDatastore.sol](src/common/RegistryDatastore.sol)

Universal storage contract for all registries. Reduces storage proof complexity for L2 resolution.

**Key Functions**:
- `getEntry(address registry, uint256 tokenId)`: Fetch subregistry and resolver
- `setSubregistry(uint256 tokenId, address subregistry)`: Update subregistry (caller must be registry)
- `setResolver(uint256 tokenId, address resolver)`: Update resolver

**Storage Structure**:
```solidity
struct Entry {
    address subregistry;  // Registry for subdomains
    address resolver;     // Resolver for this name
    uint64 flags;         // Implementation-specific data (e.g., expiry)
}
```

#### `PermissionedRegistry` - Standard Implementation
[src/common/registry/PermissionedRegistry.sol](src/common/registry/PermissionedRegistry.sol)

Feature-complete registry with role-based access control:
- ERC1155 NFT for subdomains
- Enhanced Access Control with 32 roles
- Expiry management
- Metadata support (name, description, image)

#### `ERC1155Singleton` - Gas-Optimized NFT
[src/common/ERC1155Singleton.sol](src/common/ERC1155Singleton.sol)

Modified ERC1155 allowing only one token per ID:
- Saves gas by omitting balance tracking
- Provides `ownerOf(uint256 id)` like ERC721
- Emits transfer events for indexing

### L2 Components

#### `ETHRegistrar` - .eth Name Registration
[src/L2/registrar/ETHRegistrar.sol](src/L2/registrar/ETHRegistrar.sol)

Handles .eth second-level domain registrations on L2:

**Features**:
- Commit-reveal registration (frontrunning protection)
- Configurable pricing oracle
- Multi-token payment support (ETH, USDC, etc.)
- Minimum registration duration
- Referral system

**Registration Flow**:
```solidity
// 1. Commit to name + secret
bytes32 commitment = keccak256(abi.encode(
    label, owner, secret, subregistry, resolver, duration, referrer
));
registrar.commit(commitment);

// 2. Wait MIN_COMMITMENT_AGE (prevent frontrunning)
// 3. Complete registration
registrar.register{value: price}(
    label, owner, duration, secret, subregistry, resolver, referrer, paymentToken
);
```

#### `StandardRentPriceOracle` - Dynamic Pricing
[src/L2/registrar/StandardRentPriceOracle.sol](src/L2/registrar/StandardRentPriceOracle.sol)

Length-based pricing with premium decay for expired names:
- Shorter names cost more
- Premium starts at 100% of annual rent and decays to 0% over 21 days
- Fiat-pegged via Chainlink oracles
- Multi-token support

#### `L2EjectionController` - Name Migration
[src/L2/bridge/L2EjectionController.sol](src/L2/bridge/L2EjectionController.sol)

Manages ejection of names from L2 to L1:
```solidity
// Eject name to L1 for enhanced security
ejectionController.initiateEjection(
    label,
    l1Owner,
    l1Subregistry
);
```

### L1 Components

#### `ETHFallbackResolver` - Unified Resolution
[src/L1/resolver/ETHFallbackResolver.sol](src/L1/resolver/ETHFallbackResolver.sol)

Cross-chain resolver combining three systems:
1. **L2 Names** (via CCIP-Read): New registrations on Namechain
2. **L1 Ejected Names**: Names moved to L1 for security
3. **Legacy ENSv1**: Unmigrated names still on old registry

**Resolution Priority**:
```
Ejected on L1? → Use L1 data
  ↓ No
Migrated to v2? → Use CCIP-Read for L2
  ↓ No
Exists in v1? → Use legacy resolver
```

#### `L1EjectionController` - L1 Name Management
[src/L1/bridge/L1EjectionController.sol](src/L1/bridge/L1EjectionController.sol)

Manages ejected names on L1 and handles re-import to L2.

#### Migration Controllers
- `L1MigrationController`: Handles ENSv1 → ENSv2 migration on L1
- `L2MigrationController`: Receives migrated names on L2

### Cross-Chain Bridge

#### `BridgeEncoder` - Message Format
[src/common/bridge/BridgeEncoder.sol](src/common/bridge/BridgeEncoder.sol)

Encodes/decodes cross-chain messages:

**Message Types**:
1. **EJECTION**: Transfer name from L2 to L1
   ```solidity
   bytes memory msg = BridgeEncoder.encodeEjection(
       dnsEncodedName,
       transferData  // owner, expiry, subregistry, resolver
   );
   ```

2. **RENEWAL**: Sync expiry updates between chains
   ```solidity
   bytes memory msg = BridgeEncoder.encodeRenewal(tokenId, newExpiry);
   ```

### Resolution

#### `UniversalResolver` - One-Stop Resolution
[src/universalResolver/UniversalResolver.sol](src/universalResolver/UniversalResolver.sol)

Single contract for resolving any ENS name:
- Handles recursive registry traversal
- Supports CCIP-Read for L2 names
- Wildcard resolution
- Batch resolution

**Example**:
```solidity
// Resolve address
(bytes memory result, address resolver) = universalResolver.resolve(
    dnsEncodedName,
    abi.encodeWithSelector(IAddrResolver.addr.selector, node)
);
address resolved = abi.decode(result, (address));
```

## Getting started

### Installation

1. Install [Node.js](https://nodejs.org/) v24+
2. Install foundry: [guide](https://book.getfoundry.sh/getting-started/installation) v1.3.2+
3. Install [bun](https://bun.sh/) v1.2+
4. Install dependencies:
5. (OPTIONAL) Install [lcov](https://github.com/linux-test-project/lcov) if you want to run coverage tests
   * Mac: `brew install lcov`
   * Ubuntu: `sudo apt-get install lcov`

```sh
bun i
cd contracts
forge i
```

### Build

```sh
forge build
bun run compile:hardhat
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
bun run devnet        # runs w/last build
bun run devnet:clean  # builds, tests, runs
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
