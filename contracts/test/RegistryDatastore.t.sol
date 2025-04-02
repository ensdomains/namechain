// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/registry/RegistryDatastore.sol";

contract TestETHRegistry is Test {
    uint256 labelHash = uint256(keccak256("test"));
    RegistryDatastore datastore;
    uint64 expiryTime = uint64(block.timestamp + 100);
    uint32 data = 123;

    function setUp() public {
        datastore = new RegistryDatastore();
    }

    function test_GetSetSubregistry_MsgSender() public {
        datastore.setSubregistry(labelHash, address(this), expiryTime, data);

        (address subregistry, uint64 expiry, uint32 returnedData) = datastore.getSubregistry(labelHash);
        vm.assertEq(subregistry, address(this));
        vm.assertEq(expiry, expiryTime);
        vm.assertEq(returnedData, data);

        (subregistry, expiry, returnedData) = datastore.getSubregistry(address(this), labelHash);
        vm.assertEq(subregistry, address(this));
        vm.assertEq(expiry, expiryTime);
        vm.assertEq(returnedData, data);
    }

    function test_GetSetSubregistry_OtherRegistry() public {
        DummyRegistry r = new DummyRegistry(datastore);
        r.setSubregistry(labelHash, address(this), expiryTime, data);

        (address subregistry, uint64 expiry, uint32 returnedData) = datastore.getSubregistry(labelHash);
        vm.assertEq(subregistry, address(0));
        vm.assertEq(expiry, 0);
        vm.assertEq(returnedData, 0);

        (subregistry, expiry, returnedData) = datastore.getSubregistry(address(r), labelHash);
        vm.assertEq(subregistry, address(this));
        vm.assertEq(expiry, expiryTime);
        vm.assertEq(returnedData, data);
    }

    function test_GetSetResolver_MsgSender() public {
        datastore.setResolver(labelHash, address(this), expiryTime, data);

        (address resolver, uint64 expiry, uint32 returnedData) = datastore.getResolver(labelHash);
        vm.assertEq(resolver, address(this));
        vm.assertEq(expiry, expiryTime);
        vm.assertEq(returnedData, data);

        (resolver, expiry, returnedData) = datastore.getResolver(address(this), labelHash);
        vm.assertEq(resolver, address(this));
        vm.assertEq(expiry, expiryTime);
        vm.assertEq(returnedData, data);
    }

    function test_GetSetResolver_OtherRegistry() public {
        DummyRegistry r = new DummyRegistry(datastore);
        r.setResolver(labelHash, address(this), expiryTime, data);

        (address resolver, uint64 expiry, uint32 returnedData) = datastore.getResolver(labelHash);
        vm.assertEq(resolver, address(0));
        vm.assertEq(expiry, 0);
        vm.assertEq(returnedData, 0);

        (resolver, expiry, returnedData) = datastore.getResolver(address(r), labelHash);
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

    function setSubregistry(uint256 labelHash, address subregistry, uint64 expiry, uint32 data) public {
        datastore.setSubregistry(labelHash, subregistry, expiry, data);
    }

    function setResolver(uint256 labelHash, address resolver, uint64 expiry, uint32 data) public {
        datastore.setResolver(labelHash, resolver, expiry, data);
    }
}
