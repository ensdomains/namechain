// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {IRegistryDatastore} from "~src/common/registry/interfaces/IRegistryDatastore.sol";
import {RegistryDatastore} from "~src/common/registry/RegistryDatastore.sol";
import {LibLabel} from "~src/common/utils/LibLabel.sol";

contract RegistryDatastoreTest is Test {
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
        datastore.setEntry(id, entry);

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

    function test_NewRegistry_EmitsWhenSubregistrySet() public {
        address newSubregistry = address(0x1234);
        IRegistryDatastore.Entry memory entry = IRegistryDatastore.Entry({
            subregistry: newSubregistry,
            expiry: expiryTime,
            tokenVersionId: data,
            resolver: address(0),
            eacVersionId: 0
        });

        // Setting a new subregistry should emit event
        vm.recordLogs();
        datastore.setEntry(id, entry);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "Expected event when setting subregistry");
        assertEq(logs[0].topics[0], keccak256("NewRegistry(address)"), "Wrong event signature");
        assertEq(
            address(uint160(uint256(logs[0].topics[1]))),
            newSubregistry,
            "Wrong subregistry address"
        );
    }

    function test_NewRegistry_DoesNotEmitOnResolverUpdate() public {
        // First set a subregistry
        address subregistry = address(0x1234);
        IRegistryDatastore.Entry memory entry = IRegistryDatastore.Entry({
            subregistry: subregistry,
            expiry: expiryTime,
            tokenVersionId: data,
            resolver: address(0),
            eacVersionId: 0
        });
        datastore.setEntry(id, entry);

        // Now update only the resolver
        entry.resolver = address(0x5678);
        vm.recordLogs();
        datastore.setEntry(id, entry);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0, "Should not emit event when only updating resolver");
    }

    function test_NewRegistry_DoesNotEmitOnRenew() public {
        // First set a subregistry
        address subregistry = address(0x1234);
        IRegistryDatastore.Entry memory entry = IRegistryDatastore.Entry({
            subregistry: subregistry,
            expiry: expiryTime,
            tokenVersionId: data,
            resolver: address(0),
            eacVersionId: 0
        });
        datastore.setEntry(id, entry);

        // Now update only the expiry
        entry.expiry = expiryTime + 100;
        vm.recordLogs();
        datastore.setEntry(id, entry);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0, "Should not emit event when only updating expiry");
    }

    function test_NewRegistry_DoesNotEmitForZeroAddress() public {
        IRegistryDatastore.Entry memory entry = IRegistryDatastore.Entry({
            subregistry: address(0),
            expiry: expiryTime,
            tokenVersionId: data,
            resolver: address(0),
            eacVersionId: 0
        });

        vm.recordLogs();
        datastore.setEntry(id, entry);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0, "Should not emit event for zero address subregistry");
    }

    function test_NewRegistry_EmitsOnlyOncePerSubregistry() public {
        address subregistry = address(0x1234);
        IRegistryDatastore.Entry memory entry = IRegistryDatastore.Entry({
            subregistry: subregistry,
            expiry: expiryTime,
            tokenVersionId: data,
            resolver: address(0),
            eacVersionId: 0
        });

        // First time setting this subregistry should emit
        vm.recordLogs();
        datastore.setEntry(id, entry);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "Expected event on first occurrence");

        // Second time setting the same subregistry should not emit
        vm.recordLogs();
        datastore.setEntry(id + 1, entry);
        logs = vm.getRecordedLogs();
        assertEq(logs.length, 0, "Expected no event on second occurrence of same subregistry");
    }

    function test_NewRegistry_EmitsForDifferentSubregistries() public {
        address subregistry1 = address(0x1234);
        address subregistry2 = address(0x5678);

        IRegistryDatastore.Entry memory entry1 = IRegistryDatastore.Entry({
            subregistry: subregistry1,
            expiry: expiryTime,
            tokenVersionId: data,
            resolver: address(0),
            eacVersionId: 0
        });

        IRegistryDatastore.Entry memory entry2 = IRegistryDatastore.Entry({
            subregistry: subregistry2,
            expiry: expiryTime,
            tokenVersionId: data,
            resolver: address(0),
            eacVersionId: 0
        });

        // First subregistry should emit event
        vm.recordLogs();
        datastore.setEntry(id, entry1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "Expected event for first subregistry");
        assertEq(
            address(uint160(uint256(logs[0].topics[1]))),
            subregistry1,
            "Wrong address for subregistry1"
        );

        // Second different subregistry should also emit event
        vm.recordLogs();
        datastore.setEntry(id + 1, entry2);
        logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "Expected event for second subregistry");
        assertEq(
            address(uint160(uint256(logs[0].topics[1]))),
            subregistry2,
            "Wrong address for subregistry2"
        );
    }

    function test_NewRegistry_EmitsWhenSubregistryChanges() public {
        address subregistry1 = address(0x1234);
        address subregistry2 = address(0x5678);
        vm.recordLogs();
        // Set first subregistry
        IRegistryDatastore.Entry memory entry = IRegistryDatastore.Entry({
            subregistry: subregistry1,
            expiry: expiryTime,
            tokenVersionId: data,
            resolver: address(0),
            eacVersionId: 0
        });

        datastore.setEntry(id, entry);

        // Change to a different subregistry should emit
        entry.subregistry = subregistry2;
        datastore.setEntry(id, entry);

        // Change back to the original subregistry should NOT emit
        entry.subregistry = subregistry1;
        datastore.setEntry(id, entry);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2, "Expected event when subregistry changes");
    }

    /// @notice Test struct packing verification
    function test_EntryStructPacking() public {
        address registry = address(this);
        uint256 tokenId = 0x123456789ABCDEF0123456789ABCDEF0;
        uint256 canonicalId = LibLabel.getCanonicalId(tokenId);

        // Create entry with specific test values
        IRegistryDatastore.Entry memory entry = IRegistryDatastore.Entry({
            expiry: 0x1234567890ABCDEF, // 64-bit value
            tokenVersionId: 0x12345678, // 32-bit value
            subregistry: 0x1234567890123456789012345678901234567890, // 160-bit address
            eacVersionId: 0x87654321, // 32-bit value
            resolver: 0xaBcDef1234567890123456789012345678901234 // 160-bit address
        });

        datastore.setEntry(tokenId, entry);

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
        datastore.setEntry(id, entry);
    }
}
