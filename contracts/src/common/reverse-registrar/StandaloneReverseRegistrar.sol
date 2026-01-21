// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IExtendedResolver} from "@ens/contracts/resolvers/profiles/IExtendedResolver.sol";
import {INameResolver} from "@ens/contracts/resolvers/profiles/INameResolver.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {IENSIP16} from "../utils/IENSIP16.sol";

/// @title Standalone Reverse Registrar
/// @notice A standalone reverse registrar, detached from the ENS registry.
abstract contract StandaloneReverseRegistrar is
    ERC165,
    IExtendedResolver,
    IENSIP16,
    INameResolver,
    Context
{
    ////////////////////////////////////////////////////////////////////////
    // Constants & Immutables
    ////////////////////////////////////////////////////////////////////////

    /// @notice The namehash of the `reverse` TLD node.
    /// @dev Pre-computed: namehash("reverse") = keccak256(abi.encodePacked(bytes32(0), keccak256("reverse")))
    bytes32 internal constant _REVERSE_NODE =
        0xa097f6721ce401e757d1223a763fef49b8b5f90bb18567ddb86fd205dff71d34;

    /// @notice The keccak256 hash of the DNS-encoded parent name.
    /// @dev Used for efficient validation in `resolve()` to verify the queried name
    ///      belongs to this registrar's namespace.
    bytes32 internal immutable _SIMPLE_HASHED_PARENT;

    /// @notice The length of the DNS-encoded parent name in bytes.
    /// @dev Used in `resolve()` to validate the expected name length.
    uint256 internal immutable _PARENT_LENGTH;

    /// @notice The namehash of the parent node for this reverse registrar.
    /// @dev Computed as: keccak256(abi.encodePacked(_REVERSE_NODE, keccak256(label)))
    ///      For example, for Ethereum mainnet with label "60", this would be the namehash of "60.reverse".
    bytes32 public immutable PARENT_NODE;

    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    /// @notice Mapping from reverse node to the primary ENS name for that address.
    /// @dev The node is computed as: keccak256(abi.encodePacked(PARENT_NODE, keccak256(addressString)))
    mapping(bytes32 node => string name) internal _names;

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    /// @notice Thrown when `resolve()` is called with an unsupported resolver profile.
    /// @dev This registrar only supports the `name(bytes32)` selector.
    /// @dev Error selector: `0x7b1c461b`
    error UnsupportedResolverProfile(bytes4 selector);

    /// @notice Thrown when the queried name is not a valid ENSIP-19 reverse name for this namespace.
    /// @dev The name must be exactly 41 + PARENT_LENGTH bytes and match the expected parent suffix.
    /// @dev Error selector: `0x5fe9a5df`
    error UnreachableName(bytes name);

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    /// @notice Initialises the standalone reverse registrar with the given label.
    /// @dev Computes and stores the parent node and DNS-encoded parent hash for efficient lookups.
    /// @param label The string label for the namespace (e.g., "8000000a" for OP Mainnet).
    constructor(string memory label) {
        // Compute the namehash of "{label}.reverse"
        PARENT_NODE = keccak256(
            abi.encodePacked(_REVERSE_NODE, keccak256(abi.encodePacked(label)))
        );

        // Build the DNS-encoded parent name: {labelLength}{label}{7}reverse{0}
        bytes memory parent = abi.encodePacked(
            uint8(bytes(label).length),
            label,
            uint8(7),
            "reverse",
            uint8(0)
        );
        _SIMPLE_HASHED_PARENT = keccak256(parent);
        _PARENT_LENGTH = parent.length;
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceID
    ) public view virtual override(ERC165) returns (bool) {
        return
            interfaceID == type(IExtendedResolver).interfaceId ||
            interfaceID == type(INameResolver).interfaceId ||
            super.supportsInterface(interfaceID);
    }

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    /// @notice Returns the primary ENS name for a given reverse node.
    /// @inheritdoc INameResolver
    /// @param node The reverse node to query.
    /// @return The primary ENS name associated with the node, or an empty string if not set.
    function name(bytes32 node) external view override returns (string memory) {
        return _names[node];
    }

    /// @notice Resolves a DNS-encoded reverse name to its primary ENS name.
    /// @dev Implements ENSIP-10 wildcard resolution for reverse lookups.
    ///      Only supports the `name(bytes32)` resolver profile.
    ///
    ///      Expected name format: {40-char-hex-address}.{label}.reverse
    ///      DNS-encoded: {0x28}{40-hex-chars}{labelLen}{label}{0x07}reverse{0x00}
    ///
    /// @inheritdoc IExtendedResolver
    /// @param name The DNS-encoded reverse name to resolve.
    /// @param data The ABI-encoded function call (must be `name(bytes32)`).
    /// @return The ABI-encoded primary ENS name.
    function resolve(
        bytes calldata name,
        bytes calldata data
    ) external view override returns (bytes memory) {
        bytes4 selector = bytes4(data);

        // Only support the name(bytes32) resolver profile
        if (selector != INameResolver.name.selector) revert UnsupportedResolverProfile(selector);

        // Validate name length: 41 bytes for address component + parent suffix
        // 41 = 1 byte (length prefix) + 40 bytes (hex address without 0x)
        if (name.length != _PARENT_LENGTH + 41) revert UnreachableName(name);

        // Validate the parent suffix matches this registrar's namespace
        if (keccak256(name[41:]) != _SIMPLE_HASHED_PARENT) revert UnreachableName(name);

        // Compute the reverse node and return the stored name
        bytes32 node = keccak256(abi.encodePacked(PARENT_NODE, keccak256(name[1:41])));
        return abi.encode(_names[node]);
    }

    ////////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////////

    /// @notice Sets the primary ENS name for an address.
    /// @dev Computes the reverse node from the address and stores the name.
    ///      Emits ENSIP-16 events for indexer compatibility.
    ///
    ///      IMPORTANT: Authorisation must be checked by the caller before invoking this function.
    ///
    /// @param addr The address to set the primary name for.
    /// @param name_ The primary ENS name to associate with the address.
    function _setName(address addr, string calldata name_) internal {
        // Convert address to lowercase hex string (without 0x prefix)
        string memory label = _toAddressString(addr);

        // Compute the token ID and reverse node
        uint256 tokenId = uint256(keccak256(abi.encodePacked(label)));
        bytes32 node = keccak256(abi.encodePacked(PARENT_NODE, tokenId));

        // Reverse names never expire
        uint64 expiry = type(uint64).max;

        // Store the name
        _names[node] = name_;

        // Emit ENSIP-16 events for indexer compatibility
        emit NameRegistered(tokenId, label, expiry, _msgSender(), 0);
        emit ResolverUpdated(tokenId, address(this));
        emit NameChanged(node, name_);
    }

    /// @notice Converts an address to its lowercase hex string representation (without 0x prefix).
    /// @dev Uses inline assembly for gas efficiency. Produces exactly 40 hex characters.
    /// @param value The address to convert.
    /// @return result The lowercase hex string (40 bytes, no 0x prefix).
    function _toAddressString(address value) internal pure returns (string memory result) {
        /// @solidity memory-safe-assembly
        assembly {
            // Allocate memory for result string
            result := mload(0x40)
            mstore(0x40, add(result, 0x60)) // 32 (length slot) + 40 (data) padded to 64 bytes
            mstore(result, 40) // Store string length (40 hex chars)

            // Hex lookup table: "0123456789abcdef" left-aligned in a bytes32
            let table := 0x3031323334353637383961626364656600000000000000000000000000000000

            let o := add(result, 32) // Pointer to string data (after length slot)
            let v := shl(96, value) // Left-align 160-bit address in 256-bit word

            // Process 1 byte (2 nibbles) per iteration → 20 iterations for 40 hex chars
            for {
                let i := 0
            } lt(i, 20) {
                i := add(i, 1)
            } {
                let b := byte(i, v) // Extract i-th byte from left
                let pos := shl(1, i) // Output position = i * 2
                mstore8(add(o, pos), byte(shr(4, b), table)) // High nibble → ASCII
                mstore8(add(o, add(pos, 1)), byte(and(b, 0xf), table)) // Low nibble → ASCII
            }
        }
    }
}
