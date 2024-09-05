// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "src/registry/ETHRegistry.sol";
import "src/registry/RegistryDatastore.sol";
import "src/registrar/ETHRegistrar.sol";

contract TestETHRegistrar is Test, ERC1155Holder {
    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );

    RegistryDatastore datastore;
    ETHRegistry registry;
    ETHRegistrar registrar;

    function setUp() public {
        // Warp time to roughly current time
        vm.warp(1725513923);
        datastore = new RegistryDatastore();
        registry = new ETHRegistry(datastore);
        registrar = new ETHRegistrar(28 days);
        // Grant access to the registry to this contract
        registry.grantRole(registry.REGISTRAR_ROLE(), address(this));
        // Grant access to the registry to the registrar
        registry.grantRole(registry.REGISTRAR_ROLE(), address(registrar));
    }

    function test_commit() public {
        bytes32 expectedCommitment = keccak256("test");
        registrar.commit(expectedCommitment);
        assertEq(registrar.commitments(expectedCommitment), block.timestamp);
    }
}
