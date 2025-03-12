// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IRegistryMetadata.sol";

/// @title MetadataMixin
/// @notice Mixin contract for Registry implementations to delegate metadata to an external provider
/// @dev Inherit this contract to add metadata functionality to Registry contracts
abstract contract MetadataMixin {
    /// @notice The metadata provider contract
    IRegistryMetadata public immutable metadataProvider;

    /// @notice Initializes the mixin with a metadata provider
    /// @param _metadataProvider Address of the metadata provider contract
    constructor(IRegistryMetadata _metadataProvider) {
        metadataProvider = _metadataProvider;
    }

    /// @notice Returns the token URI for a given token ID
    /// @param tokenId The ID of the token to query
    /// @return URI string for the token metadata
    function tokenURI(uint256 tokenId) internal view virtual returns (string memory) {
        if (address(metadataProvider) == address(0)) {
            return "";
        }
        return metadataProvider.tokenUri(tokenId);
    }
}
