// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

bytes32 constant NODE_ANY = 0;

interface IDedicatedResolver {
    /// @notice The address could not be converted to `address`.
    /// @dev Error selector: `0x8d666f60`
    error InvalidEVMAddress(bytes addressBytes);

    /// @notice Set address for the coin type.
    ///         If coin type is EVM, require exactly 0 or 20 bytes.
    /// @param coinType The coin type.
    /// @param addressBytes The address to set.
    function setAddr(uint256 coinType, bytes calldata addressBytes) external;

    /// @notice Set a text record.
    /// @param key The key to set.
    /// @param value The value to set.
    function setText(string calldata key, string calldata value) external;

    /// @notice Set the content hash.
    /// @param hash The content hash.
    function setContenthash(bytes calldata hash) external;

    /// @dev Sets the public key.
    /// @param x The x coordinate of the pubkey.
    /// @param y The y coordinate of the pubkey.
    function setPubkey(bytes32 x, bytes32 y) external;

    /// @dev Set the ABI for the content type.
    /// @param contentType The content type.
    /// @param data The ABI data.
    function setABI(uint256 contentType, bytes calldata data) external;

    /// @dev Sets the implementer for an interface.
    /// @param interfaceId The interface ID.
    /// @param implementer The implementer address.
    function setInterface(bytes4 interfaceId, address implementer) external;

    /// @dev Set the primary name.
    /// @param name The primary name.
    function setName(string calldata name) external;
}
