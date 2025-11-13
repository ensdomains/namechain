// SPDX-License-Identifier: MIT
// Portions from OpenZeppelin Contracts (token/ERC1155/ERC1155.sol)
pragma solidity >=0.8.13;

import {
    IERC1155MetadataURI
} from "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {ERC1155Singleton} from "../erc1155/ERC1155Singleton.sol";
import {LibLabel} from "../utils/LibLabel.sol";

import {IRegistry} from "./interfaces/IRegistry.sol";
import {IRegistryDatastore} from "./interfaces/IRegistryDatastore.sol";
import {IRegistryCrier} from "./interfaces/IRegistryCrier.sol";

abstract contract BaseRegistry is IRegistry, ERC1155Singleton {
    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    IRegistryDatastore public immutable DATASTORE;
    IRegistryCrier public immutable CRIER;

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    error AccessDenied(uint256 tokenId, address owner, address caller);

    ////////////////////////////////////////////////////////////////////////
    // Modifiers
    ////////////////////////////////////////////////////////////////////////

    modifier onlyTokenOwner(uint256 tokenId) {
        address owner = ownerOf(tokenId);
        if (owner != msg.sender) {
            revert AccessDenied(tokenId, owner, msg.sender);
        }
        _;
    }

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(IRegistryDatastore datastore_, IRegistryCrier crier_) {
        DATASTORE = datastore_;
        CRIER = crier_;
    }

    /// @inheritdoc IERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC1155Singleton, IERC165) returns (bool) {
        return
            interfaceId == type(IERC1155).interfaceId ||
            interfaceId == type(IERC1155MetadataURI).interfaceId ||
            interfaceId == type(IRegistry).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    /// @notice Fetches the registry for a subdomain of the current registry.
    ///
    /// @param label The label to resolve.
    ///
    /// @return The address of the registry for this subdomain, or `address(0)` if none exists.
    function getSubregistry(string calldata label) external view virtual returns (IRegistry) {
        IRegistryDatastore.Entry memory entry = DATASTORE.getEntry(
            address(this),
            LibLabel.labelToCanonicalId(label)
        );
        return IRegistry(entry.subregistry);
    }

    /// @notice Fetches the resolver responsible for the specified label.
    ///
    /// @param label The label to fetch a resolver for.
    ///
    /// @return resolver The address of a resolver responsible for this name, or `address(0)` if none exists.
    function getResolver(string calldata label) external view virtual returns (address resolver) {
        IRegistryDatastore.Entry memory entry = DATASTORE.getEntry(
            address(this),
            LibLabel.labelToCanonicalId(label)
        );
        resolver = entry.resolver;
    }
}
