// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {Test} from "forge-std/Test.sol";

import {IRegistryDatastore} from "./../src/common/IRegistryDatastore.sol";
import {NameUtils} from "./../src/common/NameUtils.sol";
import {RegistryDatastore} from "./../src/common/RegistryDatastore.sol";

contract TestRegistryDatastore is Test {
    uint256 id = uint256(keccak256("test"));
    RegistryDatastore datastore;
    uint64 expiryTime = uint64(block.timestamp + 100);
    uint32 data = 123;

    function setUp() public {
        datastore = new RegistryDatastore();
    }

    function test_GetSetEntry_MsgSender() public {
        IRegistryDatastore.Entry memory entry = IRegistryDatastore.Entry({
            subregistry: address(this),
            expiry: expiryTime,
            tokenVersionId: data,
            resolver: address(0),
            eacVersionId: 0
        });
        datastore.setEntry(address(this), id, entry);

        IRegistryDatastore.Entry memory returnedEntry = datastore.getEntry(address(this), id);
        vm.assertEq(returnedEntry.subregistry, address(this));
        vm.assertEq(returnedEntry.expiry, expiryTime);
        vm.assertEq(returnedEntry.tokenVersionId, data);
    }

    function test_GetSetEntry_OtherRegistry() public {
        DummyRegistry r = new DummyRegistry(datastore);
        IRegistryDatastore.Entry memory entry = IRegistryDatastore.Entry({
            subregistry: address(this),
            expiry: expiryTime,
            tokenVersionId: data,
            resolver: address(0),
            eacVersionId: 0
        });
        r.setEntry(id, entry);

        IRegistryDatastore.Entry memory returnedEntry = datastore.getEntry(address(this), id);
        vm.assertEq(returnedEntry.subregistry, address(0));
        vm.assertEq(returnedEntry.expiry, 0);
        vm.assertEq(returnedEntry.tokenVersionId, 0);

        returnedEntry = datastore.getEntry(address(r), id);
        vm.assertEq(returnedEntry.subregistry, address(this));
        vm.assertEq(returnedEntry.expiry, expiryTime);
        vm.assertEq(returnedEntry.tokenVersionId, data);
    }

    function test_SetSubregistry_Setters() public {
        datastore.setSubregistry(id, address(this));
        datastore.setResolver(id, address(this));

        IRegistryDatastore.Entry memory returnedEntry = datastore.getEntry(address(this), id);
        vm.assertEq(returnedEntry.subregistry, address(this));
        vm.assertEq(returnedEntry.resolver, address(this));
    }

    function test_SetSubregistry_Resolver_OtherRegistry() public {
        DummyRegistry r = new DummyRegistry(datastore);
        r.setSubregistry(id, address(this));
        r.setResolver(id, address(this));

        IRegistryDatastore.Entry memory returnedEntry = datastore.getEntry(address(this), id);
        vm.assertEq(returnedEntry.subregistry, address(0));
        vm.assertEq(returnedEntry.resolver, address(0));

        returnedEntry = datastore.getEntry(address(r), id);
        vm.assertEq(returnedEntry.subregistry, address(this));
        vm.assertEq(returnedEntry.resolver, address(this));
    }

    /// @notice Test struct packing verification
    function test_EntryStructPacking() public {
        address registry = address(this);
        uint256 tokenId = 0x123456789ABCDEF0123456789ABCDEF0;
        uint256 canonicalId = NameUtils.getCanonicalId(tokenId);

        // Create entry with specific test values
        IRegistryDatastore.Entry memory entry = IRegistryDatastore.Entry({
            expiry: 0x1234567890ABCDEF, // 64-bit value
            tokenVersionId: 0x12345678, // 32-bit value
            subregistry: 0x1234567890123456789012345678901234567890, // 160-bit address
            eacVersionId: 0x87654321, // 32-bit value
            resolver: 0xaBcDef1234567890123456789012345678901234 // 160-bit address
        });

        datastore.setEntry(registry, tokenId, entry);

        // Calculate storage slot for entries[registry][canonicalId]
        bytes32 slot0 = keccak256(
            abi.encode(canonicalId, keccak256(abi.encode(registry, uint256(0))))
        );
        bytes32 slot1 = bytes32(uint256(slot0) + 1);

        // Read raw storage from the datastore contract
        bytes32 slot0Data = vm.load(address(datastore), slot0);
        bytes32 slot1Data = vm.load(address(datastore), slot1);

        // Verify slot 0 packing: expiry (64) + tokenVersionId (32) + subregistry (160)
        uint256 slot0Value = uint256(slot0Data);
        uint64 extractedExpiry = uint64(slot0Value & 0xFFFFFFFFFFFFFFFF);
        uint32 extractedTokenVersionId = uint32((slot0Value >> 64) & 0xFFFFFFFF);
        address extractedSubregistry = address(uint160(slot0Value >> 96));

        assertEq(extractedExpiry, entry.expiry, "Expiry mismatch in slot 0");
        assertEq(
            extractedTokenVersionId,
            entry.tokenVersionId,
            "TokenVersionId mismatch in slot 0"
        );
        assertEq(extractedSubregistry, entry.subregistry, "Subregistry mismatch in slot 0");

        // Verify slot 1 packing: eacVersionId (32) + resolver (160)
        uint256 slot1Value = uint256(slot1Data);
        uint32 extractedEacVersionId = uint32(slot1Value & 0xFFFFFFFF);
        address extractedResolver = address(uint160(slot1Value >> 32));

        assertEq(extractedEacVersionId, entry.eacVersionId, "EacVersionId mismatch in slot 1");
        assertEq(extractedResolver, entry.resolver, "Resolver mismatch in slot 1");
    }
}

contract DummyRegistry {
    RegistryDatastore datastore;

    constructor(RegistryDatastore _datastore) {
        datastore = _datastore;
    }

    function setEntry(uint256 id, IRegistryDatastore.Entry memory entry) public {
        datastore.setEntry(address(this), id, entry);
    }

    function setSubregistry(uint256 id, address subregistry) public {
        datastore.setSubregistry(id, subregistry);
    }

    function setResolver(uint256 id, address resolver) public {
        datastore.setResolver(id, resolver);
    }
}
