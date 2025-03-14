// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IRegistryMetadata.sol";

/// @title IMetadataMixin
/// @notice Interface for metadata functionality
interface IMetadataMixin {
    /// @notice Gets the metadata provider
    function metadataProvider() external view returns (IRegistryMetadata);
    
    /// @notice Returns the token URI for a given token ID
    /// @param tokenId The ID of the token to query
    /// @return URI string for the token metadata
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

/// @title MetadataMixinBase
/// @notice Contains shared functionality for metadata implementations
abstract contract MetadataMixinBase is IMetadataMixin {
    /// @notice The metadata provider contract
    IRegistryMetadata public override metadataProvider;

    /// @notice Updates the metadata provider
    /// @param _metadataProvider Address of the new metadata provider contract
    function _updateMetadataProvider(IRegistryMetadata _metadataProvider) internal virtual {
        metadataProvider = _metadataProvider;
    }
    
    /// @notice Returns the token URI for a given token ID
    /// @param tokenId The ID of the token to query
    /// @return URI string for the token metadata
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (address(metadataProvider) == address(0)) {
            return "";
        }
        return metadataProvider.tokenUri(tokenId);
    }
}
