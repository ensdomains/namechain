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
   - tokenIds change as their access control rules change or the names have regenerated after expiry/re-registration
   - Lower 32 bits may encode version, timestamp, or other metadata

2. **Canonical ID** (`uint256`): Internal stable storage key derived from token ID
   - Always has lower 32 bits zeroed out
   - Formula: `canonicalId = tokenId ^ uint32(tokenId)`

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
- **Events**: All events emit the current token ID. `TokenRegenerated(uint256 oldTokenId, uint256 newTokenId);` event tracks the transition of the token ID when it regenerates.

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

ENSv2 uses **Enhanced Access Control (EAC)**, a general-purpose access control mixin. Compared to OpenZeppelin's roles modifier, EAC adds two key features:

1. **Resource-scoped permissions** - Roles are assigned to specific resources (e.g., individual names) rather than contract-wide
2. **Paired admin roles** - Each base role has exactly one corresponding admin role (and vice-versa)

#### How EAC Works

**Resources**: A resource is any `uint256` identifier. In registries, each name is a resource identified by its canonical token ID. The special resource ID `0` (ROOT_RESOURCE) applies globally to all resources.

**Roles**: Each role occupies a 4-bit "nybble" (half-byte) in a `uint256` bitmap, storing the assignee count (max 15 per role). Roles 0-31 are "base roles" that grant specific permissions. Roles 32-63 are their corresponding "admin roles".

**Role Layout**:
```
┌────────── 128 bits ───────────┬────────── 128 bits ───────────┐
│     Admin Roles (32-63)       │     Base Roles (0-31)         │
│  Each = 4 bits (max 15 users) │  Each = 4 bits (max 15 users) │
└───────────────────────────────┴───────────────────────────────┘
```

**Permission Inheritance**: When checking permissions for a resource, EAC combines (via bitwise OR) the roles from:
- The specific resource (e.g., your name's permissions)
- The root resource (global permissions)

In the case of registry, this means root permissions are **unrevokable by name owners** - only holders of admin roles in the root resource can remove those roles.

#### EAC in Registry Contracts

In registry contracts, EAC is used with these specific behaviors:

**Resource ID Generation**: Resource IDs are generated from token IDs to maintain key invariants:
- Each time a name expires and is re-registered, it gets a new token ID and resource ID (clearing old permissions)
- Each time a new role is granted on a name, the token ID changes (preventing griefing attacks during sales/transfers)

**Registry-Specific Roles**: From [`RegistryRolesLib.sol`](src/common/registry/libraries/RegistryRolesLib.sol):

| Role | Bit Position | Admin Bit Position | Description |
|------|--------------|--------------------| ----------- |
| `ROLE_REGISTRAR` | 0 | 128 | Can register new names (root-only) |
| `ROLE_RENEW` | 4 | 132 | Can renew name registrations |
| `ROLE_SET_SUBREGISTRY` | 8 | 136 | Can change subregistry addresses |
| `ROLE_SET_RESOLVER` | 12 | 140 | Can change the resolver address |
| `ROLE_SET_TOKEN_OBSERVER` | 16 | 144 | Can set token observer contracts |
| `ROLE_BURN` | 24 | 152 | Can burn (delete) the name |
| `ROLE_CAN_TRANSFER_ADMIN` | - | 148 | Can grant/revoke transfer admin rights |

**Note**: `ROLE_REGISTRAR` is a root-only ACL since creating new subnames has no logical resource-specific equivalent (the resource doesn't exist yet).

#### Key Behaviors

1. **Admin Role Capabilities**
   - Admin roles can grant/revoke both the base role and the admin role itself
   - In registries, **only the name owner can hold admin roles**
   - All roles currently held by an owner transfer with owernship
   - **Why this restriction?** To prevent granting admin rights to another account and retaining control after a transfer. While theoretically secure (auditable), this was judged too risky.

2. **Transfer Behavior**
   - When you transfer a name, **all admin roles** transfer to the new owner
   - Existing **base roles** delegated to other accounts remain intact unless explicitly revoked
   - Example: If Alice granted Bob `ROLE_SET_RESOLVER` and transfers the name to Charlie, Charlie becomes the new admin but Bob keeps his resolver permission

3. **Token ID Regeneration**
   - Token IDs regenerate on expiry/re-registration (clears all old permissions)
   - Token IDs regenerate when granting new roles (prevents front-running during sales/transfers)
   - The underlying canonical ID remains unchanged (points to same storage)

4. **Role Delegation and Revocation**
   - **Name owners can grant base roles** to other accounts (e.g., to allow setting resolvers)
   - **Name owners can revoke their own admin/base roles** (equivalent to burning fuses in Name Wrapper)
   - Revoking roles creates permanent permission restrictions

#### Usage Examples

```solidity
// Grant a base role for a specific name
registry.grantRoles(tokenId, ROLE_SET_RESOLVER, alice);

// Grant multiple roles at once
uint256 roles = ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY;
registry.grantRoles(tokenId, roles, operator);

// Set global permissions (requires registry owner)
registry.grantRoles(ROOT_RESOURCE, ROLE_SET_RESOLVER, admin);

// Check permissions
registry.hasRoles(tokenId, ROLE_SET_RESOLVER, alice);
```

#### Creating Emancipated Names

You can create the equivalent of Name Wrapper "emancipated" names by:
1. Creating a subregistry where the owner has no root ACLs
2. Locking the subregistry into the parent registry
3. Result: Parent registry owner cannot interfere with subname operations

#### Example Usage

```solidity
import {RegistryRolesLib} from "./libraries/RegistryRolesLib.sol";

// Scenario: Delegate resolver management without transfer rights
(uint256 tokenId, ) = registry.getNameData("example");

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
[src/common/registry/RegistryDatastore.sol](src/common/registry/RegistryDatastore.sol)

Universal storage contract for all registries. Reduces storage proof complexity for L2 resolution.

**Key Functions**:
- `getEntry(address registry, uint256 tokenId)`: Fetch an entry
- `setEntry(address registry, uint256 id, Entry calldata entry)`: Set an entry
- `setSubregistry(uint256 tokenId, address subregistry)`: Update subregistry (caller must be registry)
- `setResolver(uint256 tokenId, address resolver)`: Update resolver

**Storage Structure**:
```solidity
struct Entry {
   uint64 expiry;          // Timestamp when the name expires (0 = never expires)
   uint32 tokenVersionId;  // Version counter for token regeneration (incremented on burn/remint)
   address subregistry;    // Registry contract for subdomains under this name
   uint32 eacVersionId;    // Version counter for access control changes (incremented on permission updates)
   address resolver;       // Resolver contract for name resolution data
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
[src/common/erc1155/ERC1155Singleton.sol](src/common/erc1155/ERC1155Singleton.sol)

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

#### `L2BridgeController` - Name Migration
[src/L2/bridge/L2BridgeController.sol](src/L2/bridge/L2BridgeController.sol)

Manages ejection of names from L2 to L1. Ejection is triggered by transferring the token to the bridge controller:
```solidity
// Prepare transfer data for ejection
TransferData memory transferData = TransferData({
    dnsEncodedName: LibLabel.dnsEncodeEthLabel(label),
    owner: l1Owner,
    subregistry: l1Subregistry,
    resolver: l1Resolver,
    roleBitmap: roleBitmap,
    expires: expiryTime
});

// Transfer token to bridge controller to initiate ejection
registry.safeTransferFrom(
    msg.sender,
    address(bridgeController),
    tokenId,
    1,
    abi.encode(transferData)
);
```

### L1 Components

#### `ETHTLDResolver` - Unified Resolution
[src/L1/resolver/ETHTLDResolver.sol](src/L1/resolver/ETHTLDResolver.sol)

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

#### `L1BridgeController` - L1 Name Management
[src/L1/bridge/L1BridgeController.sol](src/L1/bridge/L1BridgeController.sol)

Handles ejected names on L1 triggered by transferring name to bridge controller.

#### Migration Controllers
- `L1LockedMigrationController`: Handles ENSv1 → ENSv2 migration on L1 for locked names
- `L1UnlockedMigrationController`: Handles ENSv1 → ENSv2 migration on L1 for unlocked names

### Cross-Chain Bridge

#### `BridgeEncoderLib` - Message Format
[src/common/bridge/libraries/BridgeEncoderLib.sol](src/common/bridge/libraries/BridgeEncoderLib.sol)

Encodes/decodes cross-chain messages:

**Message Types**:
1. **EJECTION**: Transfer name from L2 to L1
   ```solidity
   bytes memory msg = BridgeEncoderLib.encodeEjection(
       transferData  // owner, expiry, subregistry, resolver
   );
   ```

2. **RENEWAL**: Sync expiry updates between chains
   ```solidity
   bytes memory msg = BridgeEncoderLib.encodeRenewal(tokenId, newExpiry);
   ```

### Resolution

#### `UniversalResolverV2` - One-Stop Resolution
[src/universalResolver/UniversalResolverV2.sol](src/universalResolver/UniversalResolverV2.sol)

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
