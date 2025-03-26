// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {UserRegistry} from "../src/L2/UserRegistry.sol";
import {ETHRegistry} from "../src/L2/ETHRegistry.sol";
import {IRegistry} from "../src/common/IRegistry.sol";
import {RegistryDatastore} from "../src/common/RegistryDatastore.sol";
import {IRegistryMetadata} from "../src/common/IRegistryMetadata.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SimpleRegistryMetadata} from "../src/common/SimpleRegistryMetadata.sol";

contract SimpleRegistryMetadataTest is Test, ERC1155Holder {
    RegistryDatastore datastore;
    UserRegistry registry;
    ETHRegistry parentRegistry;
    SimpleRegistryMetadata metadata;

    function setUp() public {
        datastore = new RegistryDatastore();
        metadata = new SimpleRegistryMetadata();
        
        parentRegistry = new ETHRegistry(datastore, metadata);
        parentRegistry.grantRole(parentRegistry.REGISTRAR_ROLE(), address(this));
        
        registry = new UserRegistry(
            parentRegistry,
            "test",
            datastore,
            metadata
        );

        parentRegistry.register("test", address(this), registry, address(0), 0, uint64(block.timestamp + 1000));
    }

    function test_registry_metadata_token_uri() public {
        string memory expectedUri = "ipfs://test";
        uint256 tokenId = uint256(keccak256(bytes("sub")));

        registry.mint("sub", address(this), registry, 0);

        assertEq(registry.uri(tokenId), "");
        
        metadata.grantRole(metadata.UPDATE_ROLE(), address(this));
        metadata.setTokenUri(tokenId, expectedUri);

        assertEq(metadata.tokenUri(tokenId), expectedUri);
        assertEq(registry.uri(tokenId), expectedUri);
    }

    function test_registry_metadata_unauthorized() public {
        uint256 tokenId = uint256(keccak256(bytes("sub")));
        string memory expectedUri = "ipfs://test";

        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), metadata.UPDATE_ROLE()));
        metadata.setTokenUri(tokenId, expectedUri);
    }

    function test_registry_metadata_supports_interface() public view {
        assertEq(metadata.supportsInterface(type(IRegistryMetadata).interfaceId), true);
        assertEq(metadata.supportsInterface(type(IERC165).interfaceId), true);
    }
} 