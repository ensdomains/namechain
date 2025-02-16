// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import {ETHRegistryController} from "src/registry/ETHRegistryController.sol";
import {ETHRegistry} from "src/registry/ETHRegistry.sol";
import {RegistryDatastore} from "src/registry/RegistryDatastore.sol";
import {IRegistry} from "src/registry/IRegistry.sol";

contract TestETHRegistryController is Test {
    ETHRegistryController controller;
    ETHRegistry registry;
    RegistryDatastore datastore;

    address owner = address(2);

    function setUp() public {
        datastore = new RegistryDatastore();
        registry = new ETHRegistry(datastore);
        controller = new ETHRegistryController(address(registry));
        
        registry.grantRole(registry.REGISTRAR_ROLE(), address(controller));
    }

    function test_register() public {
        uint256 tokenId = controller.register(
            "test",
            owner,
            IRegistry(address(registry)),
            0,
            uint64(block.timestamp + 86400)
        );

        assertEq(registry.ownerOf(tokenId), owner);
    }

    function test_available() public {
        uint256 tokenId = controller.register(
            "test",
            owner,
            IRegistry(address(registry)),
            0,
            uint64(block.timestamp + 100)
        );

        assertFalse(controller.available(tokenId));
        
        vm.warp(block.timestamp + 101);
        assertTrue(controller.available(tokenId));
    }

    function test_renew() public {
        uint256 tokenId = controller.register(
            "test",
            owner,
            IRegistry(address(registry)),
            0,
            uint64(block.timestamp + 100)
        );
        
        uint64 newExpiry = uint64(block.timestamp + 200);
        controller.renew(tokenId, newExpiry);

        (uint64 expiry,) = registry.nameData(tokenId);
        assertEq(expiry, newExpiry);
    }
} 