// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IRegistryMetadata.sol";
import "./MetadataMixinBase.sol";

/// @title MetadataMixin
/// @notice Mixin contract for Registry implementations to delegate metadata to an external provider
/// @dev Inherit this contract to add metadata functionality to Registry contracts
abstract contract MetadataMixin is MetadataMixinBase {
    /// @notice Initializes the mixin with a metadata provider
    /// @param _metadataProvider Address of the metadata provider contract
    constructor(IRegistryMetadata _metadataProvider) {
        metadataProvider = _metadataProvider;
    }
}
