# L2 Reverse Registrar

The L2 Reverse Registrar is a combination of a resolver and a reverse registrar that allows the name to be set for a particular reverse node.

## Setting records

You can set records using one of the follow functions:

`setName()` - uses the msg.sender's address and allows you to set a record for that address only

`setNameForAddr()` - uses the address parameter instead of `msg.sender` and checks if the `msg.sender` is authorised by checking if the contract's owner (via the Ownable pattern) is the msg.sender

`setNameForAddrWithSignature()` - uses the address parameter instead of `msg.sender` and allows authorisation via a signature

`setNameForOwnableWithSignature()` - uses the address parameter instead of `msg.sender`. The sender is authorised by checking if the contract's owner (via the Ownable pattern) is the msg.sender, which then checks that the signer has authorised the record on behalf of msg.sender using `ERC1271` (or `ERC6492`)

## Signatures for setting records

Signatures are all plaintext, prefixed with `\x19Ethereum Signed Message:\n<length of message>` as defined in ERC-191.

### Field definitions

| Field | Type | Description |
|-------|------|-------------|
| `name` | `string` | The ENS name to set as primary (e.g., `vitalik.eth`). |
| `address` | `address` | The address for which the primary name is being set. EIP-55 checksummed. |
| `owner` | `address` | The address that owns the contract for which the primary name is being set. EIP-55 checksummed. Only applicable for `setNameForOwnableWithSignature`. |
| `chainList` | `string` | Comma-separated list of chains in format `{name} ({chainId})`, ordered by ascending chain ID. |
| `expirationTime` | `string` | ISO 8601 UTC datetime when signature expires (max 1 hour from current time). |
| `validatorAddress` | `address` | The signature validator contract address. EIP-55 checksummed. |

### `setNameForAddrWithSignature`

```
You are setting your ENS primary name to:
{name}

Address: {address}
Chains: {chainList}
Expires At: {expirationTime}

---
Validator: {validatorAddress}
```

### `setNameForOwnableWithSignature`

```
You are setting the ENS primary name for a contract you own to:
{name}

Contract Address: {address}
Owner: {owner}
Chains: {chainList}
Expires At: {expirationTime}

---
Validator: {validatorAddress}
```