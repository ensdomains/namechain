// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {Test} from "forge-std/Test.sol";

import {
    RegistryDatastore,
    IRegistryDatastore,
    IRegistry,
    LibLabel
} from "~src/registry/RegistryDatastore.sol";

contract RegistryDatastoreTest is Test {
    RegistryDatastore datastore;

    IRegistryDatastore.Entry entry =
        IRegistryDatastore.Entry({
            expiry: 0x1234567890ABCDEF, // 64-bit value
            tokenVersionId: 0x12345678, // 32-bit value
            subregistry: IRegistry(0x1234567890123456789012345678901234567890),
            eacVersionId: 0x87654321, // 32-bit value
            resolver: 0xaBcDef1234567890123456789012345678901234
        });

    uint256 id = LibLabel.labelToCanonicalId("test");

    function setUp() external {
        datastore = new RegistryDatastore();
    }

    function test_getSetEntry_msgSender() external {
        datastore.setEntry(id, entry);
        _same(datastore.getEntry(IRegistry(address(this)), id), entry);
    }

    function test_getSetEntry_otherRegistry() external {
        address otherRegistry = makeAddr("other");
        vm.prank(otherRegistry);
        datastore.setEntry(id, entry);
        _same(datastore.getEntry(IRegistry(otherRegistry), id), entry);
        delete entry;
        _same(datastore.getEntry(IRegistry(address(this)), id), entry);
    }

    /// @notice Test struct packing verification
    function test_entryStorage() external view {
        bytes32 slot;
        assembly {
            slot := entry.slot
        }
        uint256 slot0 = uint256(vm.load(address(this), slot));
        uint256 slot1 = uint256(vm.load(address(this), bytes32(uint256(slot) + 1)));
        _same(
            entry,
            IRegistryDatastore.Entry({
                expiry: uint64(slot0),
                tokenVersionId: uint32(slot0 >> 64),
                subregistry: IRegistry(address(uint160(slot0 >> 96))),
                eacVersionId: uint32(slot1),
                resolver: address(uint160(slot1 >> 32))
            })
        );
        assertEq(uint64(0), uint64(slot1 >> 192), "unused");
    }

    function _same(
        IRegistryDatastore.Entry memory a,
        IRegistryDatastore.Entry memory b
    ) internal pure {
        vm.assertEq(address(a.subregistry), address(b.subregistry), "subregistry");
        vm.assertEq(a.resolver, b.resolver, "resolver");
        vm.assertEq(a.expiry, b.expiry, "expiry");
        vm.assertEq(a.tokenVersionId, b.tokenVersionId, "tokenVersionId");
        vm.assertEq(a.eacVersionId, b.eacVersionId, "eacVersionId");
    }
}
