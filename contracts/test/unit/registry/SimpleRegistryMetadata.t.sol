// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {Test} from "forge-std/Test.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {EACBaseRolesLib} from "~src/access-control/EnhancedAccessControl.sol";
import {
    IEnhancedAccessControl
} from "~src/access-control/interfaces/IEnhancedAccessControl.sol";
import {IRegistryMetadata} from "~src/registry/interfaces/IRegistryMetadata.sol";
import {RegistryRolesLib} from "~src/registry/libraries/RegistryRolesLib.sol";
import {PermissionedRegistry} from "~src/registry/PermissionedRegistry.sol";
import {RegistryDatastore} from "~src/registry/RegistryDatastore.sol";
import {SimpleRegistryMetadata} from "~src/registry/SimpleRegistryMetadata.sol";
import {MockHCAFactoryBasic} from "~test/mocks/MockHCAFactoryBasic.sol";

contract SimpleRegistryMetadataTest is Test, ERC1155Holder {
    RegistryDatastore datastore;
    MockHCAFactoryBasic hcaFactory;
    PermissionedRegistry registry;
    SimpleRegistryMetadata metadata;

    // Hardcoded role constants
    uint256 constant ROLE_UPDATE_METADATA = 1 << 0;
    uint256 constant ROLE_UPDATE_METADATA_ADMIN = ROLE_UPDATE_METADATA << 128;

    uint256 constant DEFAULT_ROLE_BITMAP =
        RegistryRolesLib.ROLE_SET_SUBREGISTRY | RegistryRolesLib.ROLE_SET_RESOLVER;
    uint256 constant ROOT_RESOURCE = 0;

    function setUp() public {
        datastore = new RegistryDatastore();
        hcaFactory = new MockHCAFactoryBasic();
        metadata = new SimpleRegistryMetadata(hcaFactory);
        // Use the valid ALL_ROLES value for deployer roles
        uint256 deployerRoles = EACBaseRolesLib.ALL_ROLES;
        registry = new PermissionedRegistry(
            datastore,
            hcaFactory,
            metadata,
            address(this),
            deployerRoles
        );
    }

    function test_registry_metadata_token_uri() public {
        uint256 tokenId = registry.register(
            "test",
            address(this),
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp + 1000)
        );

        assertEq(registry.uri(tokenId), "");

        string memory expectedUri = "ipfs://test";
        metadata.setTokenUri(tokenId, expectedUri);
        assertEq(metadata.tokenUri(tokenId), expectedUri);
        assertEq(registry.uri(tokenId), expectedUri);
    }

    function test_registry_metadata_unauthorized() public {
        (uint256 tokenId, ) = registry.getNameData("test");
        string memory expectedUri = "ipfs://test";

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                ROOT_RESOURCE,
                ROLE_UPDATE_METADATA,
                address(1)
            )
        );
        vm.prank(address(1));
        metadata.setTokenUri(tokenId, expectedUri);
    }

    function test_registry_metadata_supports_interface() public view {
        assertEq(metadata.supportsInterface(type(IRegistryMetadata).interfaceId), true);
        assertEq(metadata.supportsInterface(type(IEnhancedAccessControl).interfaceId), true);
        assertEq(metadata.supportsInterface(type(IERC165).interfaceId), true);
    }
}
