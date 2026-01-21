// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {SignatureUtils} from "@ens/contracts/reverseRegistrar/SignatureUtils.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {
    StandaloneReverseRegistrar
} from "../../common/reverse-registrar/StandaloneReverseRegistrar.sol";
import {LibISO8601} from "../../common/utils/LibISO8601.sol";

import {IL2ReverseRegistrar} from "./interfaces/IL2ReverseRegistrar.sol";

/// @title L2 Reverse Registrar
/// @notice A reverse registrar for L2 chains that allows users to set their ENS primary name.
/// @dev Deployed to each L2 chain. Supports signature-based claims for both EOAs and contracts.
contract L2ReverseRegistrar is IL2ReverseRegistrar, ERC165, StandaloneReverseRegistrar {
    using SignatureUtils for bytes;

    ////////////////////////////////////////////////////////////////////////
    // Constants & Immutables
    ////////////////////////////////////////////////////////////////////////

    /// @notice The chain ID of the chain this contract is deployed to.
    /// @dev Derived from the coin type during construction.
    uint256 public immutable CHAIN_ID;

    /// @notice First 32 bytes of the validator address checksum string ("0x" + first 30 hex chars).
    /// @dev Pre-computed at construction for gas-efficient message building.
    bytes32 private immutable _VALIDATOR_ADDR_PART1;

    /// @notice Last 10 bytes of the validator address checksum string (chars 32-41), left-aligned.
    /// @dev Pre-computed at construction for gas-efficient message building.
    bytes32 private immutable _VALIDATOR_ADDR_PART2;

    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    /// @notice Mapping of message hashes to their used status for replay protection.
    /// @dev The message hash serves as a unique nonce for each signature claim.
    mapping(bytes32 messageHash => bool used) private _nonces;

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    /// @notice Thrown when the specified address is not the owner of the target contract.
    /// @dev Error selector: `0x4570a024`
    error NotOwnerOfContract();

    /// @notice Thrown when the current chain ID is not included in the claim's chain ID array.
    /// @dev Error selector: `0xc8ca4826`
    error CurrentChainNotFound();

    /// @notice Thrown when attempting to use a message hash that has already been consumed.
    /// @dev Error selector: `0x1fb09b80`
    error NonceAlreadyUsed();

    /// @notice Thrown when the caller is not authorised to perform the action.
    /// @dev Error selector: `0xd7a2ae6a`
    error Unauthorised();

    ////////////////////////////////////////////////////////////////////////
    // Modifiers
    ////////////////////////////////////////////////////////////////////////

    /// @notice Checks if the caller is authorised to act on behalf of the given address.
    /// @dev Authorised if caller is the address itself, or if caller owns the contract at addr.
    /// @param addr The address to check authorisation for.
    modifier authorised(address addr) {
        if (addr != msg.sender && !_ownsContract(addr, msg.sender)) {
            revert Unauthorised();
        }
        _;
    }

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    /// @notice Initialises the contract with the coin type for this L2 chain.
    /// @dev Pre-computes the validator address checksum string for gas-efficient message building.
    /// @param coinType The ENSIP-11 coin type for this chain.
    /// @param label The hex string label for the coin type (used in reverse node computation).
    constructor(uint256 coinType, string memory label) StandaloneReverseRegistrar(coinType, label) {
        CHAIN_ID = (0x7fffffff & coinType) >> 0;

        // Validator address checksum string is 42 bytes: "0x" + 40 hex characters
        // Pre-compute and store in two 32-byte immutables for efficient assembly access
        string memory addressString = _toChecksumHexString(address(this));
        bytes32 part1;
        bytes32 part2;
        assembly {
            // First 32 bytes of the validator address checksum string ("0x" + first 30 hex chars).
            part1 := mload(add(addressString, 32))
            // Bytes starting at offset 32 (bytes 32-63, but only 32-41 are valid = last 10 hex chars)
            part2 := mload(add(addressString, 64))
        }
        _VALIDATOR_ADDR_PART1 = part1;
        _VALIDATOR_ADDR_PART2 = part2;
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceID
    ) public view override(ERC165, StandaloneReverseRegistrar) returns (bool) {
        return
            interfaceID == type(IL2ReverseRegistrar).interfaceId ||
            super.supportsInterface(interfaceID);
    }

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    /// @inheritdoc IL2ReverseRegistrar
    function setName(string calldata name) external {
        _setName(msg.sender, name);
    }

    /// @inheritdoc IL2ReverseRegistrar
    function setNameForAddr(address addr, string calldata name) external authorised(addr) {
        _setName(addr, name);
    }

    /// @inheritdoc IL2ReverseRegistrar
    function setNameForAddrWithSignature(
        NameClaim calldata claim,
        bytes calldata signature
    ) external {
        string memory chainIdsString = _validateChainIds(claim.chainIds);

        bytes32 message = _createNameForAddrWithSignatureMessageHash(claim, chainIdsString);
        _validateMessageAsNonce(message);

        signature.validateSignatureWithExpiry(claim.addr, message, claim.expirationTime);

        _setName(claim.addr, claim.name);
    }

    /// @inheritdoc IL2ReverseRegistrar
    function setNameForOwnableWithSignature(
        NameClaim calldata claim,
        address owner,
        bytes calldata signature
    ) external {
        string memory chainIdsString = _validateChainIds(claim.chainIds);

        if (!_ownsContract(claim.addr, owner)) revert NotOwnerOfContract();

        bytes32 message = _createNameForOwnableWithSignatureMessageHash(
            claim,
            owner,
            chainIdsString
        );
        _validateMessageAsNonce(message);

        signature.validateSignatureWithExpiry(owner, message, claim.expirationTime);

        _setName(claim.addr, claim.name);
    }

    ////////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////////

    /// @notice Validates and consumes a message hash as a nonce for replay protection.
    /// @dev Reverts if the message hash has already been used.
    /// @param messageHash The message hash to validate and consume.
    function _validateMessageAsNonce(bytes32 messageHash) internal {
        if (_nonces[messageHash]) revert NonceAlreadyUsed();
        _nonces[messageHash] = true;
    }

    /// @notice Checks if the provided address owns the contract via the Ownable interface.
    /// @dev Returns false if the target is not a contract or doesn't implement Ownable.
    /// @param contractAddr The address of the contract to check.
    /// @param addr The address to check ownership against.
    /// @return True if addr is the owner of contractAddr, false otherwise.
    function _ownsContract(address contractAddr, address addr) internal view returns (bool) {
        if (contractAddr.code.length == 0) return false;
        try Ownable(contractAddr).owner() returns (address owner) {
            return owner == addr;
        } catch {
            return false;
        }
    }

    /// @notice Validates that the current chain ID is in the provided array and builds the display string.
    /// @dev Reverts if the current chain ID is not found in the array.
    /// @param chainIds The array of chain IDs to validate.
    /// @return chainIdsString The chain IDs formatted as a comma-separated string.
    function _validateChainIds(
        uint256[] calldata chainIds
    ) internal view returns (string memory chainIdsString) {
        bool containsCurrentChain = false;

        for (uint256 i = 0; i < chainIds.length; ++i) {
            if (chainIds[i] == CHAIN_ID) containsCurrentChain = true;
            chainIdsString = string.concat(chainIdsString, _toString(chainIds[i]));
            if (i < chainIds.length - 1) chainIdsString = string.concat(chainIdsString, ", ");
        }

        if (!containsCurrentChain) revert CurrentChainNotFound();

        return chainIdsString;
    }

    /// @notice Creates the EIP-191 message hash for setNameForAddrWithSignature.
    ///
    ///         Message format:
    ///         ```
    ///         You are setting your ENS primary name to:
    ///         {name}
    ///
    ///         Address: {address}
    ///         Chains: {chainList}
    ///         Expires At: {expirationTime}
    ///
    ///         ---
    ///         Validator: {validatorAddress}
    ///         Nonce: {nonce}
    ///         ```
    ///
    /// @param claim The name claim data.
    /// @param chainIdsString The pre-validated chain IDs as a display string.
    /// @return digest The EIP-191 signed message hash.
    function _createNameForAddrWithSignatureMessageHash(
        NameClaim calldata claim,
        string memory chainIdsString
    ) internal view returns (bytes32 digest) {
        string memory name = claim.name;
        string memory addrString = _toChecksumHexString(claim.addr);
        string memory expiresAtString = LibISO8601.toISO8601(claim.expirationTime);
        string memory nonceString = _toString(claim.nonce);

        // Cache immutables for assembly access
        bytes32 validatorPart1 = _VALIDATOR_ADDR_PART1;
        bytes32 validatorPart2 = _VALIDATOR_ADDR_PART2;

        // Build message in memory as bytes
        bytes memory message;
        assembly {
            // Paris-compatible memory copy helper (replaces mcopy from Cancun)
            // Copies in 32-byte chunks; safe here since subsequent writes overwrite any overshoot
            function _memcpy(dest, src, len) {
                for {
                    let i := 0
                } lt(i, len) {
                    i := add(i, 32)
                } {
                    mstore(add(dest, i), mload(add(src, i)))
                }
            }

            // Get free memory pointer - reserve space for length, then build message
            message := mload(0x40)
            let ptr := add(message, 32) // Start writing after length slot

            // "You are setting your ENS primary" (32 bytes)
            mstore(ptr, 0x596f75206172652073657474696e6720796f757220454e53207072696d617279)
            // " name to:\n" (10 bytes)
            mstore(add(ptr, 32), 0x206e616d6520746f3a0a00000000000000000000000000000000000000000000)
            ptr := add(ptr, 42)

            // Copy name (variable length)
            let nameLen := mload(name)
            _memcpy(ptr, add(name, 32), nameLen)
            ptr := add(ptr, nameLen)

            // "\n\nAddress: " (11 bytes)
            mstore(ptr, 0x0a0a416464726573733a20000000000000000000000000000000000000000000)
            ptr := add(ptr, 11)

            // Copy addrString (42 bytes)
            _memcpy(ptr, add(addrString, 32), 42)
            ptr := add(ptr, 42)

            // "\nChains: " (9 bytes)
            mstore(ptr, 0x0a436861696e733a200000000000000000000000000000000000000000000000)
            ptr := add(ptr, 9)

            // Copy chainIdsString (variable length)
            let chainLen := mload(chainIdsString)
            _memcpy(ptr, add(chainIdsString, 32), chainLen)
            ptr := add(ptr, chainLen)

            // "\nExpires At: " (13 bytes)
            mstore(ptr, 0x0a457870697265732041743a2000000000000000000000000000000000000000)
            ptr := add(ptr, 13)

            // Copy expiresAtString (20 bytes fixed - ISO8601 format)
            _memcpy(ptr, add(expiresAtString, 32), 20)
            ptr := add(ptr, 20)

            // "\n\n---\nValidator: " (17 bytes)
            mstore(ptr, 0x0a0a2d2d2d0a56616c696461746f723a20000000000000000000000000000000)
            ptr := add(ptr, 17)

            // Write validator address using pre-computed immutables (42 bytes total).
            // Each mstore writes 32 bytes; the overlap beyond byte 42 is overwritten by subsequent data.
            mstore(ptr, validatorPart1)
            mstore(add(ptr, 32), validatorPart2)
            ptr := add(ptr, 42)

            // "\nNonce: " (8 bytes)
            mstore(ptr, 0x0a4e6f6e63653a20000000000000000000000000000000000000000000000000)
            ptr := add(ptr, 8)

            // Copy nonceString (variable length)
            let nonceLen := mload(nonceString)
            _memcpy(ptr, add(nonceString, 32), nonceLen)
            ptr := add(ptr, nonceLen)

            // Store final message length and update free memory pointer
            mstore(message, sub(ptr, add(message, 32)))
            mstore(0x40, ptr)
        }

        return _toEthSignedMessageHash(message);
    }

    /// @notice Creates the EIP-191 message hash for setNameForOwnableWithSignature.
    ///
    ///         Message format:
    ///         ```
    ///         You are setting the ENS primary name for a contract you own to:
    ///         {name}
    ///
    ///         Contract Address: {address}
    ///         Owner: {owner}
    ///         Chains: {chainList}
    ///         Expires At: {expirationTime}
    ///
    ///         ---
    ///         Validator: {validatorAddress}
    ///         Nonce: {nonce}
    ///         ```
    ///
    /// @param claim The name claim data.
    /// @param owner The owner address of the contract.
    /// @param chainIdsString The pre-validated chain IDs as a display string.
    /// @return digest The EIP-191 signed message hash.
    function _createNameForOwnableWithSignatureMessageHash(
        NameClaim calldata claim,
        address owner,
        string memory chainIdsString
    ) internal view returns (bytes32 digest) {
        string memory name = claim.name;
        string memory addrString = _toChecksumHexString(claim.addr);
        string memory ownerString = _toChecksumHexString(owner);
        string memory expiresAtString = LibISO8601.toISO8601(claim.expirationTime);
        string memory nonceString = _toString(claim.nonce);

        // Cache immutables for assembly access
        bytes32 validatorPart1 = _VALIDATOR_ADDR_PART1;
        bytes32 validatorPart2 = _VALIDATOR_ADDR_PART2;

        // Build message in memory as bytes
        bytes memory message;
        assembly {
            // Paris-compatible memory copy helper (replaces mcopy from Cancun)
            // Copies in 32-byte chunks; safe here since subsequent writes overwrite any overshoot
            function _memcpy(dest, src, len) {
                for {
                    let i := 0
                } lt(i, len) {
                    i := add(i, 32)
                } {
                    mstore(add(dest, i), mload(add(src, i)))
                }
            }

            // Get free memory pointer - reserve space for length, then build message
            message := mload(0x40)
            let ptr := add(message, 32) // Start writing after length slot

            // "You are setting the ENS primary " (32 bytes)
            mstore(ptr, 0x596f75206172652073657474696e672074686520454e53207072696d61727920)
            // "name for a contract you own to:\n" (32 bytes)
            mstore(add(ptr, 32), 0x6e616d6520666f72206120636f6e747261637420796f75206f776e20746f3a0a)
            ptr := add(ptr, 64)

            // Copy name (variable length)
            let nameLen := mload(name)
            _memcpy(ptr, add(name, 32), nameLen)
            ptr := add(ptr, nameLen)

            // "\n\nContract Address: " (20 bytes)
            mstore(ptr, 0x0a0a436f6e747261637420416464726573733a20000000000000000000000000)
            ptr := add(ptr, 20)

            // Copy addrString (42 bytes)
            _memcpy(ptr, add(addrString, 32), 42)
            ptr := add(ptr, 42)

            // "\nOwner: " (8 bytes)
            mstore(ptr, 0x0a4f776e65723a20000000000000000000000000000000000000000000000000)
            ptr := add(ptr, 8)

            // Copy ownerString (42 bytes)
            _memcpy(ptr, add(ownerString, 32), 42)
            ptr := add(ptr, 42)

            // "\nChains: " (9 bytes)
            mstore(ptr, 0x0a436861696e733a200000000000000000000000000000000000000000000000)
            ptr := add(ptr, 9)

            // Copy chainIdsString (variable length)
            let chainLen := mload(chainIdsString)
            _memcpy(ptr, add(chainIdsString, 32), chainLen)
            ptr := add(ptr, chainLen)

            // "\nExpires At: " (13 bytes)
            mstore(ptr, 0x0a457870697265732041743a2000000000000000000000000000000000000000)
            ptr := add(ptr, 13)

            // Copy expiresAtString (20 bytes fixed - ISO8601 format)
            _memcpy(ptr, add(expiresAtString, 32), 20)
            ptr := add(ptr, 20)

            // "\n\n---\nValidator: " (17 bytes)
            mstore(ptr, 0x0a0a2d2d2d0a56616c696461746f723a20000000000000000000000000000000)
            ptr := add(ptr, 17)

            // Write validator address using pre-computed immutables (42 bytes total).
            // Each mstore writes 32 bytes; the overlap beyond byte 42 is overwritten by subsequent data.
            mstore(ptr, validatorPart1)
            mstore(add(ptr, 32), validatorPart2)
            ptr := add(ptr, 42)

            // "\nNonce: " (8 bytes)
            mstore(ptr, 0x0a4e6f6e63653a20000000000000000000000000000000000000000000000000)
            ptr := add(ptr, 8)

            // Copy nonceString (variable length)
            let nonceLen := mload(nonceString)
            _memcpy(ptr, add(nonceString, 32), nonceLen)
            ptr := add(ptr, nonceLen)

            // Store final message length and update free memory pointer
            mstore(message, sub(ptr, add(message, 32)))
            mstore(0x40, ptr)
        }

        return _toEthSignedMessageHash(message);
    }

    /// @notice Computes the EIP-191 signed message hash.
    /// @dev Equivalent to keccak256("\x19Ethereum Signed Message:\n" + len(message) + message).
    /// @param message The message bytes to hash.
    /// @return digest The EIP-191 signed message hash.
    function _toEthSignedMessageHash(bytes memory message) internal pure returns (bytes32 digest) {
        string memory lenString = _toString(message.length);
        assembly {
            // Paris-compatible memory copy helper (replaces mcopy from Cancun)
            // Copies in 32-byte chunks; safe here since we hash immediately after
            function _memcpy(dest, src, len) {
                for {
                    let i := 0
                } lt(i, len) {
                    i := add(i, 32)
                } {
                    mstore(add(dest, i), mload(add(src, i)))
                }
            }

            let messageLen := mload(message)
            let lenStringLen := mload(lenString)

            // Build prefixed message at free memory pointer.
            // We don't update the free memory pointer since this buffer is only used for hashing.
            let ptr := mload(0x40)

            // "\x19Ethereum Signed Message:\n" (26 bytes)
            mstore(ptr, 0x19457468657265756d205369676e6564204d6573736167653a0a000000000000)

            // Copy length string (decimal digits of message length) after prefix
            _memcpy(add(ptr, 26), add(lenString, 32), lenStringLen)

            // Copy message content after prefix + length string
            let messageStart := add(add(ptr, 26), lenStringLen)
            _memcpy(messageStart, add(message, 32), messageLen)

            // Compute the final EIP-191 hash: keccak256(prefix || lenString || message)
            digest := keccak256(ptr, add(add(26, lenStringLen), messageLen))
        }
    }

    /// @notice Converts an address to its EIP-55 checksummed hex string.
    /// @dev Uses inline assembly for gas efficiency. Produces "0x" + 40 hex characters.
    /// @param addr The address to convert.
    /// @return result The checksummed hex string (42 bytes).
    function _toChecksumHexString(address addr) internal pure returns (string memory result) {
        assembly {
            // Free memory pointer
            result := mload(0x40)
            mstore(0x40, add(result, 0x60)) // 32 (length) + 42 (data) = 74, round up to 96
            mstore(result, 42) // Set string length

            let ptr := add(result, 32)
            // Write "0x" prefix
            mstore8(ptr, 0x30) // '0'
            mstore8(add(ptr, 1), 0x78) // 'x'

            let hexPtr := add(ptr, 2)
            // Shift address left so first byte aligns with position 0
            let addrShifted := shl(96, addr)

            // Convert address to lowercase hex (40 chars) - process 2 hex chars per byte
            for {
                let i := 0
            } lt(i, 20) {
                i := add(i, 1)
            } {
                let byteVal := byte(i, addrShifted)
                let hi := shr(4, byteVal)
                let lo := and(byteVal, 0x0f)
                // Lookup: 0-9 -> 48-57, 10-15 -> 97-102 (a-f lowercase)
                let pos := shl(1, i) // i * 2
                mstore8(add(hexPtr, pos), add(hi, add(48, mul(39, gt(hi, 9)))))
                mstore8(add(hexPtr, add(pos, 1)), add(lo, add(48, mul(39, gt(lo, 9)))))
            }

            // Hash the 40 lowercase hex chars for checksum
            let hashVal := keccak256(hexPtr, 40)

            // Apply checksum: uppercase letters where hash nibble >= 8
            for {
                let i := 0
            } lt(i, 40) {
                i := add(i, 1)
            } {
                let charPos := add(hexPtr, i)
                let char := byte(0, mload(charPos))
                // If char is a-f (97-102) and hash nibble >= 8, uppercase it (xor with 0x20)
                // Hash nibble at position i: shift right by (252 - i*4) and mask
                if and(gt(char, 96), gt(and(shr(sub(252, shl(2, i)), hashVal), 0xf), 7)) {
                    mstore8(charPos, xor(char, 0x20))
                }
            }
        }
    }

    /// @notice Converts a uint256 to its ASCII decimal string representation.
    /// @param value The value to convert.
    /// @return result The decimal string.
    function _toString(uint256 value) internal pure returns (string memory result) {
        assembly {
            result := mload(0x40)

            switch value
            case 0 {
                mstore(0x40, add(result, 0x40)) // 32 (length slot) + 1 (data) = 33, round to 64
                mstore(result, 1) // length = 1
                mstore8(add(result, 32), 0x30) // '0'
            }
            default {
                // Count digits: `for {} temp {}` is Yul idiom for `while (temp != 0)`
                let temp := value
                let digits := 0
                for {} temp {} {
                    digits := add(digits, 1)
                    temp := div(temp, 10)
                }

                // Set length and update free memory pointer (rounded to 32-byte boundary)
                mstore(result, digits)
                mstore(0x40, add(result, and(add(add(32, digits), 31), not(31))))

                // Write digits from right to left: `for {} temp {}` is Yul idiom for `while (temp != 0)`
                let ptr := add(add(result, 32), digits)
                temp := value
                for {} temp {} {
                    ptr := sub(ptr, 1)
                    mstore8(ptr, add(48, mod(temp, 10))) // 48 = ASCII '0'
                    temp := div(temp, 10)
                }
            }
        }
    }
}
