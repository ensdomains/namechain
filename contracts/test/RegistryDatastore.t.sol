// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/common/RegistryDatastore.sol";

contract TestRegistryDatastore is Test {
    uint256 id = uint256(keccak256("test"));
    RegistryDatastore datastore;
    uint64 expiryTime = uint64(block.timestamp + 100);
    uint32 data = 123;

    function setUp() public {
        datastore = new RegistryDatastore();
    }

    function test_GetSetSubregistry_MsgSender() public {
        datastore.setSubregistry(id, address(this), expiryTime, data);

        (address subregistry, uint64 expiry, uint32 returnedData) = datastore.getSubregistry(id);
        vm.assertEq(subregistry, address(this));
        vm.assertEq(expiry, expiryTime);
        vm.assertEq(returnedData, data);

        (subregistry, expiry, returnedData) = datastore.getSubregistry(address(this), id);
        vm.assertEq(subregistry, address(this));
        vm.assertEq(expiry, expiryTime);
        vm.assertEq(returnedData, data);
    }

    function test_GetSetSubregistry_OtherRegistry() public {
        DummyRegistry r = new DummyRegistry(datastore);
        r.setSubregistry(id, address(this), expiryTime, data);

        (address subregistry, uint64 expiry, uint32 returnedData) = datastore.getSubregistry(id);
        vm.assertEq(subregistry, address(0));
        vm.assertEq(expiry, 0);
        vm.assertEq(returnedData, 0);

        (subregistry, expiry, returnedData) = datastore.getSubregistry(address(r), id);
        vm.assertEq(subregistry, address(this));
        vm.assertEq(expiry, expiryTime);
        vm.assertEq(returnedData, data);
    }

    function test_GetSetResolver_MsgSender() public {
        datastore.setResolver(id, address(this), expiryTime, data);

        (address resolver, uint64 expiry, uint32 returnedData) = datastore.getResolver(id);
        vm.assertEq(resolver, address(this));
        vm.assertEq(expiry, expiryTime);
        vm.assertEq(returnedData, data);

        (resolver, expiry, returnedData) = datastore.getResolver(address(this), id);
        vm.assertEq(resolver, address(this));
        vm.assertEq(expiry, expiryTime);
        vm.assertEq(returnedData, data);
    }

    function test_GetSetResolver_OtherRegistry() public {
        DummyRegistry r = new DummyRegistry(datastore);
        r.setResolver(id, address(this), expiryTime, data);

        (address resolver, uint64 expiry, uint32 returnedData) = datastore.getResolver(id);
        vm.assertEq(resolver, address(0));
        vm.assertEq(expiry, 0);
        vm.assertEq(returnedData, 0);

        (resolver, expiry, returnedData) = datastore.getResolver(address(r), id);
        vm.assertEq(resolver, address(this));
        vm.assertEq(expiry, expiryTime);
        vm.assertEq(returnedData, data);
    }
}

contract DummyRegistry {
    RegistryDatastore datastore;

    constructor(RegistryDatastore _datastore) {
        datastore = _datastore;
    }

    function setSubregistry(uint256 id, address subregistry, uint64 expiry, uint32 data) public {
        datastore.setSubregistry(id, subregistry, expiry, data);
    }

    function setResolver(uint256 id, address resolver, uint64 expiry, uint32 data) public {
        datastore.setResolver(id, resolver, expiry, data);
    }
}
