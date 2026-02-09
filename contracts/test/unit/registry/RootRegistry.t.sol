// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {Test, Vm} from "forge-std/Test.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {EACBaseRolesLib} from "~src/access-control/EnhancedAccessControl.sol";
import {
    IEnhancedAccessControl
} from "~src/access-control/interfaces/IEnhancedAccessControl.sol";
import {IRegistry} from "~src/registry/interfaces/IRegistry.sol";
import {RegistryRolesLib} from "~src/registry/libraries/RegistryRolesLib.sol";
import {PermissionedRegistry} from "~src/registry/PermissionedRegistry.sol";
import {RegistryDatastore} from "~src/registry/RegistryDatastore.sol";
import {SimpleRegistryMetadata} from "~src/registry/SimpleRegistryMetadata.sol";
import {MockHCAFactoryBasic} from "~test/mocks/MockHCAFactoryBasic.sol";

contract RootRegistryTest is Test, ERC1155Holder {
    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );
    event URI(string value, uint256 indexed id);
    event NameRegistered(
        uint256 indexed tokenId,
        string label,
        uint64 expiration,
        address registeredBy
    );

    RegistryDatastore datastore;
    PermissionedRegistry registry;
    MockHCAFactoryBasic hcaFactory;
    SimpleRegistryMetadata metadata;

    // Hardcoded role constants

    uint256 constant ROLE_SET_FLAGS = 1 << 4; // This one is specific to RootRegistry
    uint256 constant DEFAULT_ROLE_BITMAP =
        RegistryRolesLib.ROLE_SET_SUBREGISTRY | RegistryRolesLib.ROLE_SET_RESOLVER | ROLE_SET_FLAGS;
    uint256 constant LOCKED_RESOLVER_ROLE_BITMAP =
        RegistryRolesLib.ROLE_SET_SUBREGISTRY | ROLE_SET_FLAGS;
    uint256 constant LOCKED_SUBREGISTRY_ROLE_BITMAP =
        RegistryRolesLib.ROLE_SET_RESOLVER | ROLE_SET_FLAGS;
    uint256 constant LOCKED_FLAGS_ROLE_BITMAP =
        RegistryRolesLib.ROLE_SET_SUBREGISTRY | RegistryRolesLib.ROLE_SET_RESOLVER;
    uint64 constant MAX_EXPIRY = type(uint64).max;

    address owner = makeAddr("owner");

    function setUp() public {
        datastore = new RegistryDatastore();
        hcaFactory = new MockHCAFactoryBasic();
        metadata = new SimpleRegistryMetadata(hcaFactory);
        // Use the valid ALL_ROLES value for deployer roles
        uint256 deployerRoles = EACBaseRolesLib.ALL_ROLES;
        registry = new PermissionedRegistry(
            datastore,
            hcaFactory,
            metadata,
            address(this),
            deployerRoles
        );
        metadata.grantRootRoles(RegistryRolesLib.ROLE_REGISTRAR, address(registry));
    }

    function test_register_unlocked() public {
        uint256 tokenId = registry.register(
            "test2",
            owner,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            MAX_EXPIRY
        );
        assertTrue(
            registry.hasRoles(
                registry.getResource(tokenId),
                RegistryRolesLib.ROLE_SET_SUBREGISTRY,
                owner
            )
        );
        assertTrue(
            registry.hasRoles(
                registry.getResource(tokenId),
                RegistryRolesLib.ROLE_SET_RESOLVER,
                owner
            )
        );
        assertTrue(registry.hasRoles(registry.getResource(tokenId), ROLE_SET_FLAGS, owner));
    }

    function test_register_locked_resolver_and_subregistry() public {
        uint256 tokenId = registry.register(
            "test2",
            owner,
            registry,
            address(0),
            LOCKED_FLAGS_ROLE_BITMAP,
            MAX_EXPIRY
        );
        assertTrue(
            registry.hasRoles(
                registry.getResource(tokenId),
                RegistryRolesLib.ROLE_SET_SUBREGISTRY,
                owner
            )
        );
        assertTrue(
            registry.hasRoles(
                registry.getResource(tokenId),
                RegistryRolesLib.ROLE_SET_RESOLVER,
                owner
            )
        );
        assertFalse(registry.hasRoles(registry.getResource(tokenId), ROLE_SET_FLAGS, owner));
    }

    function test_register_locked_subregistry() public {
        uint256 tokenId = registry.register(
            "test2",
            owner,
            registry,
            address(0),
            LOCKED_SUBREGISTRY_ROLE_BITMAP,
            MAX_EXPIRY
        );
        assertFalse(
            registry.hasRoles(
                registry.getResource(tokenId),
                RegistryRolesLib.ROLE_SET_SUBREGISTRY,
                owner
            )
        );
        assertTrue(
            registry.hasRoles(
                registry.getResource(tokenId),
                RegistryRolesLib.ROLE_SET_RESOLVER,
                owner
            )
        );
        assertTrue(registry.hasRoles(registry.getResource(tokenId), ROLE_SET_FLAGS, owner));
    }

    function test_register_locked_resolver() public {
        uint256 tokenId = registry.register(
            "test2",
            owner,
            registry,
            address(0),
            LOCKED_RESOLVER_ROLE_BITMAP,
            MAX_EXPIRY
        );
        assertTrue(
            registry.hasRoles(
                registry.getResource(tokenId),
                RegistryRolesLib.ROLE_SET_SUBREGISTRY,
                owner
            )
        );
        assertFalse(
            registry.hasRoles(
                registry.getResource(tokenId),
                RegistryRolesLib.ROLE_SET_RESOLVER,
                owner
            )
        );
        assertTrue(registry.hasRoles(registry.getResource(tokenId), ROLE_SET_FLAGS, owner));
    }

    function test_set_subregistry() public {
        uint256 tokenId = registry.register(
            "test",
            owner,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            MAX_EXPIRY
        );
        vm.prank(owner);
        registry.setSubregistry(tokenId, IRegistry(address(this)));
        vm.assertEq(address(registry.getSubregistry("test")), address(this));
    }

    function test_Revert_cannot_set_locked_subregistry() public {
        uint256 tokenId = registry.register(
            "test",
            owner,
            registry,
            address(0),
            LOCKED_SUBREGISTRY_ROLE_BITMAP,
            MAX_EXPIRY
        );

        address unauthorizedCaller = address(0xdead);
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.getResource(tokenId),
                RegistryRolesLib.ROLE_SET_SUBREGISTRY,
                unauthorizedCaller
            )
        );
        vm.prank(unauthorizedCaller);
        registry.setSubregistry(tokenId, IRegistry(address(this)));
    }

    function test_set_resolver() public {
        uint256 tokenId = registry.register(
            "test",
            owner,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            MAX_EXPIRY
        );
        vm.prank(owner);
        registry.setResolver(tokenId, address(this));
        vm.assertEq(address(registry.getResolver("test")), address(this));
    }

    function test_Revert_cannot_set_locked_resolver() public {
        uint256 tokenId = registry.register(
            "test",
            owner,
            registry,
            address(0),
            LOCKED_RESOLVER_ROLE_BITMAP,
            MAX_EXPIRY
        );

        address unauthorizedCaller = address(0xdead);
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.getResource(tokenId),
                RegistryRolesLib.ROLE_SET_RESOLVER,
                unauthorizedCaller
            )
        );
        vm.prank(unauthorizedCaller);
        registry.setResolver(tokenId, address(this));
    }

    function test_register() public {
        // Setup test data
        string memory label = "testmint";

        // Start recording logs
        vm.recordLogs();

        // Call register function
        uint256 tokenId = registry.register(
            label,
            owner,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            MAX_EXPIRY
        );

        // Get recorded logs
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Verify ownership
        vm.assertEq(registry.ownerOf(tokenId), owner);

        // Verify roles were granted
        assertTrue(
            registry.hasRoles(
                registry.getResource(tokenId),
                RegistryRolesLib.ROLE_SET_SUBREGISTRY,
                owner
            )
        );
        assertTrue(
            registry.hasRoles(
                registry.getResource(tokenId),
                RegistryRolesLib.ROLE_SET_RESOLVER,
                owner
            )
        );
        assertTrue(registry.hasRoles(registry.getResource(tokenId), ROLE_SET_FLAGS, owner));

        // Verify subregistry was set
        vm.assertEq(address(registry.getSubregistry(label)), address(registry));

        // Verify events - check each log
        bool foundTransferEvent = false;
        bool foundNameRegisteredEvent = false;

        for (uint256 i = 0; i < logs.length; i++) {
            bytes32 topic0 = logs[i].topics[0];

            // TransferSingle event
            if (topic0 == keccak256("TransferSingle(address,address,address,uint256,uint256)")) {
                foundTransferEvent = true;
                address operator = address(uint160(uint256(logs[i].topics[1])));
                address from = address(uint160(uint256(logs[i].topics[2])));
                address to = address(uint160(uint256(logs[i].topics[3])));

                // The operator is the caller of the register function, which is this test contract
                assertEq(operator, address(this));
                assertEq(from, address(0));
                assertEq(to, owner);

                (uint256 id, uint256 value) = abi.decode(logs[i].data, (uint256, uint256));
                assertEq(id, tokenId);
                assertEq(value, 1);
            }
            // NameRegistered event
            else if (topic0 == keccak256("NameRegistered(uint256,string,uint64,address)")) {
                foundNameRegisteredEvent = true;
                assertEq(logs[i].topics.length, 2);
                assertEq(uint256(logs[i].topics[1]), tokenId);

                (string memory labelValue, uint64 expirationValue, address registeredByValue) = abi
                    .decode(logs[i].data, (string, uint64, address));
                assertEq(keccak256(bytes(labelValue)), keccak256(bytes(label)));
                assertEq(expirationValue, MAX_EXPIRY);
                assertEq(registeredByValue, address(this));
            }
        }

        assertTrue(foundTransferEvent, "No TransferSingle event found");
        assertTrue(foundNameRegisteredEvent, "No NameRegistered event found");
    }

    function test_Revert_register_without_permission() public {
        // Setup test data
        string memory label = "testmint";
        address unauthorizedCaller = makeAddr("unauthorized");

        // First, revoke the REGISTRAR role from the test contract
        // since it was granted in the constructor to the deployer (this test contract)
        registry.revokeRootRoles(RegistryRolesLib.ROLE_REGISTRAR, address(this));

        // Verify the test contract no longer has the role
        assertFalse(registry.hasRootRoles(RegistryRolesLib.ROLE_REGISTRAR, address(this)));

        // The test fails since no one has permission
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.ROOT_RESOURCE(),
                RegistryRolesLib.ROLE_REGISTRAR,
                unauthorizedCaller
            )
        );
        vm.prank(unauthorizedCaller);
        registry.register(label, owner, registry, address(0), DEFAULT_ROLE_BITMAP, MAX_EXPIRY);
    }
}
