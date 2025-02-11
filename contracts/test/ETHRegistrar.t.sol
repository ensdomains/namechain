// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import {ETHRegistrar} from "src/registry/ETHRegistrar.sol";
import {ETHRegistry} from "src/registry/ETHRegistry.sol";
import {RegistryDatastore} from "src/registry/RegistryDatastore.sol";
import {IRegistry} from "src/registry/IRegistry.sol";

contract TestETHRegistrar is Test {
    ETHRegistrar registrar;
    ETHRegistry registry;
    RegistryDatastore datastore;

    address controller = address(1);
    address owner = address(2);

    function setUp() public {
        datastore = new RegistryDatastore();
        registry = new ETHRegistry(datastore);
        registrar = new ETHRegistrar(address(registry));
        
        registry.grantRole(registry.REGISTRAR_ROLE(), address(registrar));
    }

    function test_addController() public {
        registrar.addController(controller);
        assertTrue(registrar.controllers(controller));
    }

    function test_removeController() public {
        registrar.addController(controller);
        registrar.removeController(controller);
        assertFalse(registrar.controllers(controller));
    }

    function test_Revert_addZeroController() public {
        vm.expectRevert("ETHRegistrar: zero address");
        registrar.addController(address(0));
    }

    function test_Revert_nonControllerRegister() public {
        vm.expectRevert("ETHRegistrar: not controller");
        registrar.register("test", owner, IRegistry(address(0)), 0, uint64(block.timestamp + 86400));
    }

    function test_register() public {
        registrar.addController(controller);
        
        vm.startPrank(controller);
        uint256 tokenId = registrar.register(
            "test",
            owner,
            IRegistry(address(registry)),
            0,
            uint64(block.timestamp + 86400)
        );
        vm.stopPrank();

        assertEq(registry.ownerOf(tokenId), owner);
    }

    function test_available() public {
        registrar.addController(controller);
        
        vm.startPrank(controller);
        uint256 tokenId = registrar.register(
            "test",
            owner,
            IRegistry(address(registry)),
            0,
            uint64(block.timestamp + 100)
        );
        vm.stopPrank();

        assertFalse(registrar.available(tokenId));
        
        vm.warp(block.timestamp + 101);
        assertTrue(registrar.available(tokenId));
    }

    function test_renew() public {
        registrar.addController(controller);
        
        vm.startPrank(controller);
        uint256 tokenId = registrar.register(
            "test",
            owner,
            IRegistry(address(registry)),
            0,
            uint64(block.timestamp + 100)
        );
        
        uint64 newExpiry = uint64(block.timestamp + 200);
        registrar.renew(tokenId, newExpiry);
        vm.stopPrank();

        (uint64 expiry,) = registry.nameData(tokenId);
        assertEq(expiry, newExpiry);
    }

    function test_Revert_nonControllerRenew() public {
        registrar.addController(controller);
        
        vm.prank(controller);
        uint256 tokenId = registrar.register(
            "test",
            owner,
            IRegistry(address(registry)),
            0,
            uint64(block.timestamp + 100)
        );

        vm.expectRevert("ETHRegistrar: not controller");
        registrar.renew(tokenId, uint64(block.timestamp + 200));
    }
} 