// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/registry/RegistryDatastore.sol";

contract TestETHRegistry is Test {
    uint256 labelHash = uint256(keccak256("test"));
    RegistryDatastore datastore;
    uint64 expiryTime = uint64(block.timestamp + 100);

    function setUp() public {
        datastore = new RegistryDatastore();
    }

    function test_GetSetSubregistry_MsgSender() public {
        // set subregistry
        datastore.setSubregistry(labelHash, address(this), expiryTime);

        (address subregistry, uint64 expiry) = datastore.getSubregistry(labelHash);
        vm.assertEq(subregistry, address(this));
        vm.assertEq(expiry, expiryTime);

        (subregistry, expiry) = datastore.getSubregistry(address(this), labelHash);
        vm.assertEq(subregistry, address(this));
        vm.assertEq(expiry, expiryTime);
    }

    function test_GetSetSubregistry_OtherRegistry() public {
        DummyRegistry r = new DummyRegistry(datastore);
        r.setSubregistry(labelHash, address(this), expiryTime);

        (address subregistry, uint64 expiry) = datastore.getSubregistry(labelHash);
        vm.assertEq(subregistry, address(0));
        vm.assertEq(expiry, 0);

        (subregistry, expiry) = datastore.getSubregistry(address(r), labelHash);
        vm.assertEq(subregistry, address(this));
        vm.assertEq(expiry, expiryTime);
    }

    function test_GetSetResolver_MsgSender() public {
        datastore.setResolver(labelHash, address(this), expiryTime);

        (address resolver, uint64 expiry) = datastore.getResolver(labelHash);
        vm.assertEq(resolver, address(this));
        vm.assertEq(expiry, expiryTime);

        (resolver, expiry) = datastore.getResolver(address(this), labelHash);
        vm.assertEq(resolver, address(this));
        vm.assertEq(expiry, expiryTime);
    }

    function test_GetSetResolver_OtherRegistry() public {
        DummyRegistry r = new DummyRegistry(datastore);
        r.setResolver(labelHash, address(this), expiryTime);

        (address resolver, uint64 expiry) = datastore.getResolver(labelHash);
        vm.assertEq(resolver, address(0));
        vm.assertEq(expiry, 0);

        (resolver, expiry) = datastore.getResolver(address(r), labelHash);
        vm.assertEq(resolver, address(this));
        vm.assertEq(expiry, expiryTime);
    }
}

contract DummyRegistry {
    RegistryDatastore datastore;

    constructor(RegistryDatastore _datastore) {
        datastore = _datastore;
    }

    function setSubregistry(uint256 labelHash, address subregistry, uint64 expiry) public {
        datastore.setSubregistry(labelHash, subregistry, expiry);
    }

    function setResolver(uint256 labelHash, address resolver, uint64 expiry) public {
        datastore.setResolver(labelHash, resolver, expiry);
    }
}
