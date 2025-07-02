// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {PermissionedRegistry} from "../src/common/PermissionedRegistry.sol";
import {IRegistry} from "../src/common/IRegistry.sol";
import {RegistryDatastore} from "../src/common/RegistryDatastore.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {BaseUriRegistryMetadata} from "../src/common/BaseUriRegistryMetadata.sol";
import {IRegistryMetadata} from "../src/common/IRegistryMetadata.sol";
import {EnhancedAccessControl} from "../src/common/EnhancedAccessControl.sol";

contract BaseUriRegistryMetadataTest is Test, ERC1155Holder {
    RegistryDatastore datastore;
    PermissionedRegistry registry;
    PermissionedRegistry parentRegistry;
    BaseUriRegistryMetadata metadata;

    // Hardcoded role constants
    uint256 constant ROLE_UPDATE_METADATA = 0x1;
    bytes32 constant ROOT_RESOURCE = 0;

    function setUp() public {
        datastore = new RegistryDatastore();
        metadata = new BaseUriRegistryMetadata();
        
        // Use a defined ALL_ROLES value for deployer roles
        uint256 deployerRoles = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
        registry = new PermissionedRegistry(
            datastore,
            metadata,
            deployerRoles
        );
    }

    function test_registry_metadata() public {
        string memory expectedUri = "https://app.ens.domains/metadata/";
        metadata.setTokenBaseUri(expectedUri);
        assertEq(metadata.tokenUri(1), expectedUri);
    }

    function test_registry_metadata_from_registry() public {
        // Test through the registry's URI function
        uint256 tokenId = registry.register("test", address(this), registry, address(0), 0, type(uint64).max);
        
        string memory expectedUri = "https://app.ens.domains/metadata/";
        metadata.setTokenBaseUri(expectedUri);
        
        assertEq(registry.uri(tokenId), expectedUri);
    }

    function test_registry_metadata_empty() public view {
        // Default should be empty
        assertEq(metadata.tokenUri(1), "");
    }

    function test_registry_metadata_various_tokens() public {
        string memory expectedUri = "https://app.ens.domains/metadata/";
        metadata.setTokenBaseUri(expectedUri);
        
        // Multiple different token IDs should return the same base URI
        assertEq(metadata.tokenUri(1), expectedUri);
        assertEq(metadata.tokenUri(42), expectedUri);
        assertEq(metadata.tokenUri(999999), expectedUri);
    }

    function test_registry_metadata_admin_can_update() public {
        string memory expectedUri = "ipfs://test/";
        metadata.setTokenBaseUri(expectedUri);
        assertEq(metadata.tokenUri(1), expectedUri);
        
        // Admin can update it
        string memory newUri = "https://newdomain.com/";
        metadata.setTokenBaseUri(newUri);
        assertEq(metadata.tokenUri(1), newUri);
    }

    function test_registry_metadata_unauthorized() public {
        string memory expectedUri = "ipfs://test/";

        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, ROOT_RESOURCE, ROLE_UPDATE_METADATA, address(1))); 
        vm.prank(address(1));
        metadata.setTokenBaseUri(expectedUri);
    }

    function test_registry_metadata_supports_interface() public view {
        assertEq(metadata.supportsInterface(type(IRegistryMetadata).interfaceId), true);
        assertEq(metadata.supportsInterface(type(EnhancedAccessControl).interfaceId), true);
        assertEq(metadata.supportsInterface(type(IERC165).interfaceId), true);
    }

    // Role bitmaps for different permission configurations
    uint256 constant ROLE_SET_SUBREGISTRY = 0x100;
    uint256 constant ROLE_SET_RESOLVER = 0x1000;
    uint256 constant ROLE_SET_FLAGS = 0x10000;
    uint256 constant defaultRoleBitmap = ROLE_SET_SUBREGISTRY | ROLE_SET_RESOLVER;
} 