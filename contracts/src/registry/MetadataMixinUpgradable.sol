// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./IRegistryMetadata.sol";
import "./MetadataMixinBase.sol";

/// @title MetadataMixinUpgradeable
/// @notice Upgradeable mixin contract for Registry implementations to delegate metadata to an external provider
/// @dev Inherit this contract to add metadata functionality to Registry contracts
abstract contract MetadataMixinUpgradable is Initializable, MetadataMixinBase {
    /// @notice Initializes the mixin with a metadata provider
    /// @param _metadataProvider Address of the metadata provider contract
    function __MetadataMixin_init(IRegistryMetadata _metadataProvider) internal onlyInitializing {
        __MetadataMixin_init_unchained(_metadataProvider);
    }
    
    function __MetadataMixin_init_unchained(IRegistryMetadata _metadataProvider) internal onlyInitializing {
        metadataProvider = _metadataProvider;
    }
    
    uint256[49] private __gap;
}
