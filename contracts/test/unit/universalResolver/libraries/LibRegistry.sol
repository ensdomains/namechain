// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {Test} from "forge-std/Test.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {EACBaseRolesLib} from "~src/common/access-control/EnhancedAccessControl.sol";
import {IHCAFactoryBasic} from "~src/common/hca/interfaces/IHCAFactoryBasic.sol";
import {
    PermissionedRegistry,
    IRegistryMetadata
} from "~src/common/registry/PermissionedRegistry.sol";
import {RegistryDatastore} from "~src/common/registry/RegistryDatastore.sol";
import {LibRegistry, IRegistry, NameCoder} from "~src/universalResolver/libraries/LibRegistry.sol";

contract LibRegistryTest is Test, ERC1155Holder {
    RegistryDatastore datastore;
    PermissionedRegistry rootRegistry;
    address resolverAddress = makeAddr("resolver");

    function _createRegistry() internal returns (PermissionedRegistry) {
        return
            new PermissionedRegistry(
                datastore,
                IHCAFactoryBasic(address(0)),
                IRegistryMetadata(address(0)),
                address(this),
                EACBaseRolesLib.ALL_ROLES
            );
    }
    function _register(
        PermissionedRegistry parentRegistry,
        string memory label,
        IRegistry registry,
        address resolver
    ) internal {
        parentRegistry.register(
            label,
            address(this),
            registry,
            resolver,
            EACBaseRolesLib.ALL_ROLES,
            uint64(block.timestamp + 1000)
        );
    }

    function setUp() public {
        datastore = new RegistryDatastore();
        rootRegistry = _createRegistry();
    }

    function test_readLabel_root() external pure {
        bytes memory name = NameCoder.encode("");
        assertEq(LibRegistry.readLabel(name, 0), "");
    }
    function test_readLabel_eth() external pure {
        bytes memory name = NameCoder.encode("eth");
        assertEq(LibRegistry.readLabel(name, 0), "eth");
        assertEq(LibRegistry.readLabel(name, 4), ""); // 3eth
    }
    function test_readLabel_test_eth() external pure {
        bytes memory name = NameCoder.encode("test.eth");
        assertEq(LibRegistry.readLabel(name, 0), "test");
        assertEq(LibRegistry.readLabel(name, 5), "eth"); // 4test
        assertEq(LibRegistry.readLabel(name, 9), ""); // 4test3eth
    }

    function _readLabel(bytes memory name, uint256 offset) public pure returns (string memory) {
        return LibRegistry.readLabel(name, offset);
    }
    function test_Revert_readLabel_invalidOffset() external {
        vm.expectRevert();
        this._readLabel("", 1);
    }
    function test_Revert_readLabel_invalidEncoding() external {
        vm.expectRevert();
        this._readLabel("0x01", 0);
    }
    function test_revert_readLabel_junkAtEnd() external {
        vm.expectRevert();
        this._readLabel("0x0000", 0);
    }

    function _expectFindResolver(
        bytes memory name,
        uint256 resolverOffset,
        address parentRegistry,
        IRegistry[] memory registries
    ) internal view {
        (, address resolver, bytes32 node, uint256 offset) = LibRegistry.findResolver(
            rootRegistry,
            name,
            0
        );
        assertEq(resolver, resolverAddress, "resolver");
        assertEq(node, NameCoder.namehash(name, 0), "node");
        assertEq(offset, resolverOffset, "offset");
        assertEq(
            address(LibRegistry.findParentRegistry(rootRegistry, name, 0)),
            parentRegistry,
            "parent"
        );
        uint256 i;
        for (offset = 0; i < registries.length; i++) {
            assertEq(
                address(LibRegistry.findExactRegistry(rootRegistry, name, offset)),
                address(registries[i]),
                "exact"
            );
            (, offset) = NameCoder.readLabel(name, offset);
        }
        assertEq(i, registries.length, "count");
    }

    function test_findResolver_eth() external {
        bytes memory name = NameCoder.encode("eth");
        //     name:  eth
        // registry: <eth> <root>
        // resolver:   X
        vm.pauseGasMetering();
        PermissionedRegistry ethRegistry = _createRegistry();
        rootRegistry.register(
            "eth",
            address(this),
            ethRegistry,
            resolverAddress,
            EACBaseRolesLib.ALL_ROLES,
            uint64(block.timestamp + 1000)
        );
        vm.resumeGasMetering();

        IRegistry[] memory v = new IRegistry[](2);
        v[0] = ethRegistry;
        v[1] = rootRegistry;
        _expectFindResolver(name, 0, address(rootRegistry), v);
    }

    function test_findResolver_resolverOnParent() external {
        bytes memory name = NameCoder.encode("test.eth");
        //     name:  test . eth
        // registry: <test> <eth> <root>
        // resolver:   X
        vm.pauseGasMetering();
        PermissionedRegistry ethRegistry = _createRegistry();
        PermissionedRegistry testRegistry = _createRegistry();
        _register(rootRegistry, "eth", ethRegistry, address(0));
        _register(ethRegistry, "test", testRegistry, resolverAddress);
        vm.resumeGasMetering();

        IRegistry[] memory v = new IRegistry[](3);
        v[0] = testRegistry;
        v[1] = ethRegistry;
        v[2] = rootRegistry;
        _expectFindResolver(name, 0, address(ethRegistry), v);
    }

    function test_findResolver_resolverOnRoot() external {
        bytes memory name = NameCoder.encode("sub.test.eth");
        //     name:  sub . test . eth
        // registry:       <test> <eth> <root>
        // resolver:                X
        vm.pauseGasMetering();
        PermissionedRegistry ethRegistry = _createRegistry();
        PermissionedRegistry testRegistry = _createRegistry();
        _register(rootRegistry, "eth", ethRegistry, resolverAddress);
        _register(ethRegistry, "test", testRegistry, address(0));
        vm.resumeGasMetering();

        IRegistry[] memory v = new IRegistry[](4);
        v[1] = testRegistry;
        v[2] = ethRegistry;
        v[3] = rootRegistry;
        _expectFindResolver(name, 9, address(testRegistry), v); // 3sub4test
    }

    function test_findResolver_virtual() external {
        bytes memory name = NameCoder.encode("a.bb.test.eth");
        //     name:  a . bb . test . eth
        // registry:          <test> <eth> <root>
        // resolver:                   X
        vm.pauseGasMetering();
        PermissionedRegistry ethRegistry = _createRegistry();
        PermissionedRegistry testRegistry = _createRegistry();
        _register(rootRegistry, "eth", ethRegistry, resolverAddress);
        _register(ethRegistry, "test", testRegistry, address(0));
        vm.resumeGasMetering();

        IRegistry[] memory v = new IRegistry[](5);
        v[2] = testRegistry;
        v[3] = ethRegistry;
        v[4] = rootRegistry;
        _expectFindResolver(name, 10, address(0), v); // 1a2bb4test
    }
}
