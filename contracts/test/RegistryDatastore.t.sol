// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/common/RegistryDatastore.sol";
import "../src/common/IRegistryDatastore.sol";

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
