# L2 Reverse Resolution via CCIP-Read Issue

## Overview

We've implemented L2 primary name support for Namechain, allowing users to set reverse resolution records on L2. The basic L2 functionality works, but cross-chain L1→L2 resolution via CCIP-read is failing.

## What Works ✅

- **L2ReverseRegistrar deployed on L2** - Users can set their L2 primary names
- **Direct L2 queries work** - Calling `L2ReverseRegistrar.nameForAddr()` on L2 returns the correct name
- **Basic test passes** - See "should set and retrieve L2 primary name" test

## What's Broken ❌

**L1→L2 CCIP-read resolution fails** with error:
```
Encoded function signature "0x31c1980f" not found on ABI
```

## Architecture

### Components

1. **L2ReverseRegistrar** (L2)
   - Location: Deployed via [deploy/l2/04_L2ReverseRegistrar.ts](deploy/l2/04_L2ReverseRegistrar.ts)
   - Contract: `lib/ens-contracts/contracts/reverseRegistrar/L2ReverseRegistrar.sol`
   - Storage: `mapping(address => string) internal _names` at slot 0
   - Coin Type: `2163142382` (for Namechain chain ID `0xeeeeee`)

2. **NamechainReverseResolver** (L1)
   - Location: Deployed via [deploy/l1/03_NamechainReverseResolver.ts](deploy/l1/03_NamechainReverseResolver.ts)
   - Contract: `ChainReverseResolver` from `lib/ens-contracts`
   - Purpose: Resolves L2 names from L1 using CCIP-read
   - Registered at: `80eeeeee.reverse` in ReverseRegistry

3. **Unruggable Gateway (URG)**
   - Verifier: `UncheckedVerifier` (deployed in test setup)
   - Gateway URL: `http://127.0.0.1:3001` (local test setup)
   - Purpose: Provides storage proofs for L2 state

### Expected Flow

```
User calls UniversalResolverV2.reverse(address, coinType)
  ↓
UniversalResolverV2 looks up "{coinType}.reverse" in ReverseRegistry
  ↓
Finds NamechainReverseResolver (ChainReverseResolver)
  ↓
ChainReverseResolver._resolveName() triggers CCIP-read
  ↓
Throws OffchainLookup error with gateway URLs
  ↓
Client/Gateway fetches storage proof from L2 for names[address]
  ↓
Client calls ChainReverseResolver.resolveNameCallback() with proof
  ↓
UncheckedVerifier verifies proof
  ↓
Returns name from L2
```

### Actual Behavior

The call fails during the CCIP-read callback phase with:
```
ContractFunctionRevertedError: The contract function "reverse" reverted with the following reason:
Encoded function signature "0x31c1980f" not found on ABI.
```

## Tests

### Passing Test
```bash
bun test test/e2e/resolve.test.ts --test-name-pattern="should set and retrieve L2 primary name"
```

This test verifies:
- L2 primary name can be set via `setL2PrimaryName()`
- Name can be retrieved via `L2ReverseRegistrar.nameForAddr()`
- Coin type is correct (`2163142382`)

### Failing Test
```bash
bun test test/e2e/resolve.test.ts --test-name-pattern="should resolve L2 primary name from L1 via CCIP-read"
```

This test attempts to:
1. Set L2 primary name on L2
2. Call `UniversalResolverV2.reverse()` from L1
3. Expect CCIP-read to fetch the name from L2

**Fails at step 2 with the function signature error:**
```
ContractFunctionExecutionError: The contract function "reverse" reverted with the following reason:
Encoded function signature "0x31c1980f" not found on ABI.
Make sure you are using the correct ABI and that the function exists on it.
You can look up the signature here: https://openchain.xyz/signatures?query=0x31c1980f.

Contract Call:
  address:   0xd8a5a9b31c3c0232e196d518e89fd8bf83acad43
  function:  reverse(bytes lookupAddress, uint256 coinType)
  args:             (0x70997970C51812dc3A010C7d01b50e0d17dc79C8, 2163142382)
```

## Investigation Areas

### Possible Causes

1. **Gateway/Verifier Configuration**
   - The gateway might not be handling the CCIP-read request correctly
   - The verifier might be missing required functionality
   - Gateway URLs might not be accessible during the callback phase

2. **ChainReverseResolver Callback**
   - Function signature `0x31c1980f` is being called but doesn't exist
   - This might be a dynamically constructed callback selector
   - The resolver might be trying to call a non-existent function on itself or another contract

3. **Storage Proof Format**
   - L2ReverseRegistrar stores names at slot 0: `mapping(address => string) _names`
   - ChainReverseResolver expects to read from this slot
   - The proof format might not match expectations

4. **ReverseRegistry Registration**
   - NamechainReverseResolver is registered at `{l2CoinType}.reverse`
   - This registration might not be working correctly with PermanentRegistry
   - UniversalResolverV2 might not be finding the resolver

### Debug Steps

1. **Check if NamechainReverseResolver is deployed**
   ```bash
   # Look for deployment logs
   bun test test/e2e/resolve.test.ts --test-name-pattern="should resolve L2" 2>&1 | grep -i "namechain"
   ```

2. **Verify registration in ReverseRegistry**
   - Check if `80eeeeee.reverse` resolves to NamechainReverseResolver
   - Verify the resolver address is correct

3. **Test CCIP-read directly on ChainReverseResolver**
   - Call `ChainReverseResolver.resolve()` directly
   - See if it throws the correct OffchainLookup error

4. **Check gateway logs**
   - The URG gateway at `http://127.0.0.1:3001` should show requests
   - Look for errors in gateway processing

5. **Decode function selector**
   ```bash
   cast 4byte 0x31c1980f
   ```
   This might reveal what function is being called

## Files Modified

- ✅ [deploy/l2/04_L2ReverseRegistrar.ts](deploy/l2/04_L2ReverseRegistrar.ts) - L2 deployment
- ✅ [deploy/l1/03_NamechainReverseResolver.ts](deploy/l1/03_NamechainReverseResolver.ts) - L1 deployment
- ✅ [script/setup.ts](script/setup.ts) - Added contracts and helper method
- ✅ [test/e2e/resolve.test.ts](test/e2e/resolve.test.ts) - Added tests
- ✅ [src/common/registry/PermanentRegistry.sol](src/common/registry/PermanentRegistry.sol) - Fixed compilation errors

## Reference Implementations

The implementation follows the Arbitrum pattern:
- [lib/ens-contracts/deploy/reverseregistrar/02_deploy_chain_reverse_resolver/00_arbitrum.ts](../lib/ens-contracts/deploy/reverseregistrar/02_deploy_chain_reverse_resolver/00_arbitrum.ts)

ChainReverseResolver contract:
- [lib/ens-contracts/contracts/reverseResolver/ChainReverseResolver.sol](../lib/ens-contracts/contracts/reverseResolver/ChainReverseResolver.sol)

## Help Needed

We need help diagnosing why the CCIP-read callback is failing with "function signature 0x31c1980f not found". The basic L2 functionality works perfectly, but the cross-chain resolution via Unruggable Gateway is broken.

## Critical Finding: Function 0x31c1980f Identified

**Function selector `0x31c1980f` is `proveRequest(bytes,(bytes))`**

From `IGatewayProtocol` interface in Unruggable Gateway:
```solidity
function proveRequest(
    bytes memory context,
    GatewayRequest memory req
) external pure returns (bytes memory);
```

**Source**:
- Found in `lib/unruggable-gateways/contracts/IGatewayProtocol.sol`
- Reference: https://github.com/nxt3d/ecs/blob/8713e12145c6626502c8de8a372c31af50958590/test/fixtures/gateway-data.json#L15

### What This Means

The error indicates that during the CCIP-read flow, something is trying to call `proveRequest()` on a contract that doesn't implement `IGatewayProtocol`. This function is part of the gateway protocol for processing off-chain lookup requests.

**Updated Questions:**
1. ✅ **SOLVED**: `0x31c1980f` = `proveRequest(bytes,(bytes))` from `IGatewayProtocol`
2. Is the contract at `0xd8a5a9b31c3c0232e196d518e89fd8bf83acad43` (UniversalResolverV2) missing `IGatewayProtocol` implementation?
3. Should ChainReverseResolver implement `IGatewayProtocol` instead of just `GatewayFetchTarget`?
4. Is there a mismatch between the gateway version and the resolver contracts?
