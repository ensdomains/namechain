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
    bytes16 private constant _HEX_DIGITS = "0123456789abcdef";

    bytes32 private constant _REVERSE_NODE =
        0xa097f6721ce401e757d1223a763fef49b8b5f90bb18567ddb86fd205dff71d34;

    uint256 public immutable COIN_TYPE;

    bytes32 public immutable PARENT_NODE;

    bytes32 public immutable SIMPLE_HASHED_PARENT;

    uint256 public immutable PARENT_LENGTH;

    /// @notice The mapping of nodes to names.
    mapping(bytes32 node => string name) internal _names;

    /// @notice `resolve()` was called with a profile other than `name()` or `addr(*)`.
    /// @dev Error selector: `0x7b1c461b`
    error UnsupportedResolverProfile(bytes4 selector);

    /// @notice `name` is not a valid DNS-encoded ENSIP-19 reverse name or namespace.
    /// @dev Error selector: `0x5fe9a5df`
    error UnreachableName(bytes name);

    constructor(uint256 coinType, string memory label) {
        COIN_TYPE = coinType;
        PARENT_NODE = keccak256(
            abi.encodePacked(_REVERSE_NODE, keccak256(abi.encodePacked(label)))
        );
        bytes memory parent = abi.encodePacked(
            uint8(bytes(label).length),
            label,
            uint8(7),
            "reverse",
            uint8(0)
        );
        SIMPLE_HASHED_PARENT = keccak256(parent);
        PARENT_LENGTH = parent.length;
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceID
    ) public view virtual override(ERC165) returns (bool) {
        return
            interfaceID == type(IExtendedResolver).interfaceId ||
            interfaceID == type(IENSIP16).interfaceId ||
            interfaceID == type(INameResolver).interfaceId ||
            super.supportsInterface(interfaceID);
    }

    function name(bytes32 node) external view override returns (string memory) {
        return _names[node];
    }

    function resolve(
        bytes calldata name,
        bytes calldata data
    ) external view override returns (bytes memory) {
        bytes4 selector = bytes4(data);

        if (selector != INameResolver.name.selector) revert UnsupportedResolverProfile(selector);

        // 41 = length of the address string + prefixed length byte
        if (name.length != PARENT_LENGTH + 41) revert UnreachableName(name);
        if (keccak256(name[41:]) != SIMPLE_HASHED_PARENT) revert UnreachableName(name);

        bytes32 node = keccak256(abi.encodePacked(PARENT_NODE, keccak256(name[1:41])));
        return abi.encode(_names[node]);
    }

    /// @notice Sets the name for an address.
    ///
    /// @dev Authorisation should be checked before calling.
    ///
    /// @param addr The address to set the name for.
    /// @param name_ The name to set.
    function _setName(address addr, string calldata name_) internal {
        string memory label = _toAddressString(addr);
        uint256 tokenId = uint256(keccak256(abi.encodePacked(label)));
        uint64 expiry = type(uint64).max;
        bytes32 node = keccak256(abi.encodePacked(PARENT_NODE, tokenId));

        _names[node] = name_;

        // TODO: add context field
        emit NameRegistered(tokenId, label, expiry, _msgSender(), 0);
        emit ResolverUpdated(tokenId, address(this));
        emit NameChanged(node, name_);
    }

    function _toAddressString(address value) internal pure returns (string memory result) {
        /// @solidity memory-safe-assembly
        assembly {
            // Allocate memory for result
            result := mload(0x40)
            mstore(0x40, add(result, 0x60)) // 32 (length) + 40 (data) padded to 64
            mstore(result, 40) // Store string length

            // Hex lookup table: "0123456789abcdef" left-aligned
            let table := 0x3031323334353637383961626364656600000000000000000000000000000000

            let o := add(result, 32) // Pointer to string data
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
