// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IAccessControl} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

import "../src/registry/RegistryDatastore.sol";
import "../src/registry/ETHRegistry.sol";
import "../src/registry/UserRegistry.sol";
import "../src/registry/BaseRegistry.sol";
import "verifiable-factory/VerifiableFactory.sol";

contract TestUserRegistry is Test, ERC1155Holder {
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);
    event SubnameCreated(string indexed label, address indexed owner, uint64 expires);
    event SubnameRenewed(uint256 indexed tokenId, uint64 newExpiration);
    event MigratedNameImported(string indexed label, address owner, uint96 flags, uint64 expires);
    event BatchMigrationCompleted(uint256 count);

    RegistryDatastore datastore;
    ETHRegistry parentRegistry;
    UserRegistry implementation;
    UserRegistry proxy;
    UserRegistry upgradeImplementation;
    VerifiableFactory factory;
    address owner = address(1);
    address migrationController = address(2);
    address user = address(3);
    uint256 salt = 123456;

    uint256 parentTokenId;
    string constant PARENT_LABEL = "eth";
    string constant TEST_LABEL = "test";

    function setUp() public {
        // Deploy base contracts
        datastore = new RegistryDatastore();
        parentRegistry = new ETHRegistry(datastore);
        parentRegistry.grantRole(parentRegistry.REGISTRAR_ROLE(), address(this));

        // Register parent name - make sure the owner is correctly set
        parentTokenId =
            parentRegistry.register(PARENT_LABEL, owner, parentRegistry, 0, uint64(block.timestamp) + 365 days);

        // Verify the owner of the parent name
        assertEq(parentRegistry.ownerOf(parentTokenId), owner);

        // Deploy implementation & proxy
        implementation = new UserRegistry();
        factory = new VerifiableFactory();

        // Encode initialization data
        bytes memory initData =
            abi.encodeWithSelector(UserRegistry.initialize.selector, parentRegistry, PARENT_LABEL, datastore, owner);

        // Deploy proxy using VerifiableFactory
        address proxyAddress = factory.deployProxy(address(implementation), salt, initData);

        // Cast proxy to UserRegistry type
        proxy = UserRegistry(proxyAddress);

        // Set up test environment - use the MIGRATION_CONTROLLER_ROLE constant directly
        bytes32 migrationRole = proxy.MIGRATION_CONTROLLER_ROLE();

        // Grant migration controller role directly with AccessControl
        vm.prank(owner);
        proxy.grantRole(migrationRole, migrationController);
    }

    // =================== Basic Functionality Tests ===================

    function test_initialization() public view {
        assertEq(address(proxy.parent()), address(parentRegistry));
        assertEq(proxy.label(), PARENT_LABEL);
        assertEq(address(proxy.datastore()), address(datastore));
        assertEq(proxy.defaultDuration(), 365 days);

        // Check roles
        assertTrue(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(proxy.hasRole(proxy.MIGRATION_CONTROLLER_ROLE(), migrationController));
    }

    function test_mint_subname() public {
        // Make sure parent registry will return owner when queried
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(parentRegistry.ownerOf.selector, parentTokenId),
            abi.encode(owner)
        );

        // Owner should be able to mint a subname
        vm.prank(owner);

        uint256 tokenId = proxy.mint(TEST_LABEL, user, IRegistry(address(0)), 0);

        // Verify token was created
        assertEq(proxy.ownerOf(tokenId), user);
        assertEq(proxy.getExpiry(tokenId), uint64(block.timestamp + 365 days));
    }

    function test_mint_subname_emits_event() public {
        // Make sure parent registry will return owner when queried
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(parentRegistry.ownerOf.selector, parentTokenId),
            abi.encode(owner)
        );

        vm.startPrank(owner);

        vm.recordLogs();
        proxy.mint(TEST_LABEL, user, IRegistry(address(0)), 0);

        vm.stopPrank();

        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Should emit NewSubname and SubnameCreated events
        bool foundNewSubname = false;
        bool foundSubnameCreated = false;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("NewSubname(string)")) {
                foundNewSubname = true;
            }
            if (entries[i].topics[0] == keccak256("SubnameCreated(string,address,uint64)")) {
                foundSubnameCreated = true;
                // Check that the indexed parameters match
                assertEq(entries[i].topics[2], bytes32(uint256(uint160(user))));
            }
        }

        assertTrue(foundNewSubname);
        assertTrue(foundSubnameCreated);
    }

    function test_Revert_mint_not_owner() public {
        // Make sure parent registry will return owner when queried
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(parentRegistry.ownerOf.selector, parentTokenId),
            abi.encode(owner)
        );

        // Non-owner should not be able to mint
        vm.prank(user);

        vm.expectRevert(abi.encodeWithSelector(BaseRegistry.AccessDenied.selector, 0, owner, user));
        proxy.mint(TEST_LABEL, user, IRegistry(address(0)), 0);
    }

    function test_burn_subname() public {
        // Make sure parent registry will return owner when queried
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(parentRegistry.ownerOf.selector, parentTokenId),
            abi.encode(owner)
        );

        // First mint a subname
        vm.prank(owner);
        uint256 tokenId = proxy.mint(TEST_LABEL, owner, IRegistry(address(0)), 0);

        // Now burn it
        vm.prank(owner);
        proxy.burn(tokenId);

        // Verify token was burned
        assertEq(proxy.ownerOf(tokenId), address(0));
    }

    function test_Revert_burn_locked_subname() public {
        console.log("TokenId used for owner check:");
        console.logBytes32(bytes32(parentTokenId));

        // Mock the correct tokenId for the parent registry's ownerOf call
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(parentRegistry.ownerOf.selector, parentTokenId),
            abi.encode(owner)
        );

        // Mint a subname with locked subregistry
        vm.prank(owner);
        uint256 tokenId = proxy.mint(TEST_LABEL, owner, IRegistry(address(0)), proxy.FLAG_SUBREGISTRY_LOCKED());

        // Try to burn it
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseRegistry.InvalidSubregistryFlags.selector, tokenId, proxy.FLAG_SUBREGISTRY_LOCKED(), 0
            )
        );
        proxy.burn(tokenId);
    }

    function test_renew_subname() public {
        // Make sure parent registry will return owner when queried
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(parentRegistry.ownerOf.selector, parentTokenId),
            abi.encode(owner)
        );

        // First mint a subname
        vm.prank(owner);
        uint256 tokenId = proxy.mint(TEST_LABEL, user, IRegistry(address(0)), 0);

        // Initial expiry
        uint64 initialExpiry = proxy.getExpiry(tokenId);

        // Renew it
        vm.prank(owner);
        proxy.renew(tokenId, 30 days);

        // Verify new expiry
        assertEq(proxy.getExpiry(tokenId), initialExpiry + 30 days);
    }

    function test_renew_subname_emits_event() public {
        // Make sure parent registry will return owner when queried
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(parentRegistry.ownerOf.selector, parentTokenId),
            abi.encode(owner)
        );

        // First mint a subname
        vm.prank(owner);
        uint256 tokenId = proxy.mint(TEST_LABEL, user, IRegistry(address(0)), 0);

        // Renew it and check event
        vm.recordLogs();
        vm.prank(owner);
        proxy.renew(tokenId, 30 days);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundEvent = false;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("SubnameRenewed(uint256,uint64)")) {
                foundEvent = true;
                assertEq(entries[i].topics[1], bytes32(tokenId));
            }
        }

        assertTrue(foundEvent);
    }

    function test_Revert_renew_expired_name() public {
        // Make sure parent registry will return owner when queried
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(parentRegistry.ownerOf.selector, parentTokenId),
            abi.encode(owner)
        );

        // First mint a subname with short expiry
        vm.prank(owner);
        uint256 tokenId = proxy.mint(TEST_LABEL, user, IRegistry(address(0)), 0);
        // Initial expiry
        uint64 initialExpiry = proxy.getExpiry(tokenId);
        // Warp past expiry
        vm.warp(initialExpiry + 1);

        // Try to renew
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(UserRegistry.NameExpired.selector, tokenId));
        proxy.renew(tokenId, 30 days);
    }

    // =================== Lock Tests ===================

    function test_lock_subname() public {
        // Make sure parent registry will return owner when queried
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(parentRegistry.ownerOf.selector, parentTokenId),
            abi.encode(owner)
        );

        // First mint a subname
        vm.prank(owner);
        uint256 tokenId = proxy.mint(TEST_LABEL, user, IRegistry(address(0)), 0);

        // Lock it
        vm.prank(user);
        proxy.lock(tokenId);

        // Verify it's locked
        assertTrue(proxy.locked(tokenId));
    }

    function test_lockResolver_subname() public {
        // Make sure parent registry will return owner when queried
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(parentRegistry.ownerOf.selector, parentTokenId),
            abi.encode(owner)
        );

        // First mint a subname
        vm.prank(owner);
        uint256 tokenId = proxy.mint(TEST_LABEL, user, IRegistry(address(0)), 0);

        // Set resolver
        vm.prank(user);
        proxy.setResolver(tokenId, address(1));

        // Lock resolver
        vm.prank(user);
        proxy.lockResolver(tokenId);

        // Try to change resolver
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseRegistry.InvalidSubregistryFlags.selector, tokenId, proxy.FLAG_RESOLVER_LOCKED(), 0
            )
        );
        proxy.setResolver(tokenId, address(2));
    }

    function test_lockFlags_subname() public {
        // Make sure parent registry will return owner when queried
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(parentRegistry.ownerOf.selector, parentTokenId),
            abi.encode(owner)
        );

        // First mint a subname
        vm.prank(owner);
        uint256 tokenId = proxy.mint(TEST_LABEL, user, IRegistry(address(0)), 0);

        // Lock flags
        vm.prank(user);
        proxy.lockFlags(tokenId);

        // Try to lock subregistry
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(BaseRegistry.InvalidSubregistryFlags.selector, tokenId, proxy.FLAG_FLAGS_LOCKED(), 0)
        );
        proxy.lock(tokenId);
    }

    // =================== Migration Controller Tests ===================

    function test_add_remove_migration_controller() public {
        // Make sure parent registry will return owner when queried
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(parentRegistry.ownerOf.selector, parentTokenId),
            abi.encode(owner)
        );

        address newController = address(4);

        // Add new controller using the role grant method (bypass onlyNameOwner)
        vm.startPrank(owner);
        proxy.grantRole(proxy.MIGRATION_CONTROLLER_ROLE(), newController);

        // Verify controller was added
        assertTrue(proxy.hasRole(proxy.MIGRATION_CONTROLLER_ROLE(), newController));

        // Remove controller using the role revoke method (bypass onlyNameOwner)
        proxy.revokeRole(proxy.MIGRATION_CONTROLLER_ROLE(), newController);
        vm.stopPrank();

        // Verify controller was removed
        assertFalse(proxy.hasRole(proxy.MIGRATION_CONTROLLER_ROLE(), newController));
    }

    function test_importMigratedName() public {
        string memory migratedLabel = "migrated";
        uint96 flags = 0;
        uint64 expires = uint64(block.timestamp + 365 days);

        // Import migrated name
        vm.prank(migrationController);
        uint256 tokenId = proxy.importMigratedName(migratedLabel, user, IRegistry(address(0)), flags, expires);

        // Verify token was created
        assertEq(proxy.ownerOf(tokenId), user);
        assertEq(proxy.getExpiry(tokenId), expires);
    }

    function test_importMigratedName_emits_event() public {
        string memory migratedLabel = "migrated";
        uint96 flags = 0;
        uint64 expires = uint64(block.timestamp + 365 days);

        // Import migrated name and check event
        vm.recordLogs();
        vm.prank(migrationController);
        proxy.importMigratedName(migratedLabel, user, IRegistry(address(0)), flags, expires);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundEvent = false;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("MigratedNameImported(string,address,uint96,uint64)")) {
                foundEvent = true;
            }
        }

        assertTrue(foundEvent);
    }

    function test_Revert_importMigratedName_not_controller() public {
        string memory migratedLabel = "migrated";
        uint96 flags = 0;
        uint64 expires = uint64(block.timestamp + 365 days);

        // Try to import migrated name from non-controller
        vm.prank(user);
        vm.expectRevert(); // AccessControl error
        proxy.importMigratedName(migratedLabel, user, IRegistry(address(0)), flags, expires);
    }

    function test_batchImportMigratedNames() public {
        string[] memory labels = new string[](2);
        labels[0] = "migrated1";
        labels[1] = "migrated2";

        address[] memory owners = new address[](2);
        owners[0] = user;
        owners[1] = address(4);

        IRegistry[] memory registries = new IRegistry[](2);
        registries[0] = IRegistry(address(0));
        registries[1] = IRegistry(address(0));

        uint96[] memory flagsArray = new uint96[](2);
        flagsArray[0] = 0;
        flagsArray[1] = 0;

        uint64[] memory expiresArray = new uint64[](2);
        expiresArray[0] = uint64(block.timestamp + 365 days);
        expiresArray[1] = uint64(block.timestamp + 730 days);

        // Batch import
        vm.prank(migrationController);
        proxy.batchImportMigratedNames(labels, owners, registries, flagsArray, expiresArray);

        // Verify tokens were created
        uint256 tokenId1 = uint256(keccak256(bytes(labels[0])));
        uint256 tokenId2 = uint256(keccak256(bytes(labels[1])));

        assertEq(proxy.ownerOf(tokenId1), owners[0]);
        assertEq(proxy.ownerOf(tokenId2), owners[1]);
        assertEq(proxy.getExpiry(tokenId1), expiresArray[0]);
        assertEq(proxy.getExpiry(tokenId2), expiresArray[1]);
    }

    function test_batchImportMigratedNames_emits_event() public {
        string[] memory labels = new string[](2);
        labels[0] = "migrated1";
        labels[1] = "migrated2";

        address[] memory owners = new address[](2);
        owners[0] = user;
        owners[1] = address(4);

        IRegistry[] memory registries = new IRegistry[](2);
        registries[0] = IRegistry(address(0));
        registries[1] = IRegistry(address(0));

        uint96[] memory flagsArray = new uint96[](2);
        flagsArray[0] = 0;
        flagsArray[1] = 0;

        uint64[] memory expiresArray = new uint64[](2);
        expiresArray[0] = uint64(block.timestamp + 365 days);
        expiresArray[1] = uint64(block.timestamp + 730 days);

        // Record logs and batch import
        vm.recordLogs();
        vm.prank(migrationController);
        proxy.batchImportMigratedNames(labels, owners, registries, flagsArray, expiresArray);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundBatchEvent = false;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("BatchMigrationCompleted(uint256)")) {
                foundBatchEvent = true;
                uint256 count = abi.decode(entries[i].data, (uint256));
                assertEq(count, 2);
            }
        }

        assertTrue(foundBatchEvent);
    }

    // =================== Upgrade Tests ===================

    function test_upgrade() public {
        // Deploy the upgrade implementation
        upgradeImplementation = new UserRegistryV2();

        // Get ERC1967 implementation slot to check implementation address
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address currentImplementation = address(uint160(uint256(vm.load(address(proxy), implementationSlot))));
        assertEq(currentImplementation, address(implementation));

        // Upgrade the proxy
        vm.prank(owner);
        proxy.upgradeToAndCall(address(upgradeImplementation), "");

        // Cast to the new version
        UserRegistryV2 upgradedProxy = UserRegistryV2(address(proxy));

        // Check that we can call the new function
        assertEq(upgradedProxy.version(), 0);

        // Ensure old state is preserved
        assertEq(address(upgradedProxy.parent()), address(parentRegistry));
        assertEq(upgradedProxy.label(), PARENT_LABEL);
        assertEq(upgradedProxy.defaultDuration(), 365 days);

        // Make sure parent registry will return owner when queried for upgradeToVersion
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(parentRegistry.ownerOf.selector, parentTokenId),
            abi.encode(owner)
        );

        // Call the upgrade function to set version
        vm.prank(owner);
        upgradedProxy.upgradeToVersion(2);

        // Verify version was updated
        assertEq(upgradedProxy.version(), 2);

        // Verify implementation address changed
        address newImplementation = address(uint160(uint256(vm.load(address(proxy), implementationSlot))));
        assertEq(newImplementation, address(upgradeImplementation));
    }

    function test_Revert_upgrade_not_authorized() public {
        // Deploy the upgrade implementation
        upgradeImplementation = new UserRegistryV2();

        // Attempt unauthorized upgrade
        vm.prank(user); // Not the owner
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, address(0))
        );
        proxy.upgradeToAndCall(address(upgradeImplementation), "");
    }

    function test_storage_integrity_after_upgrade() public {
        // Make sure parent registry will return owner when queried
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(parentRegistry.ownerOf.selector, parentTokenId),
            abi.encode(owner)
        );

        // First mint a subname
        vm.prank(owner);
        uint256 tokenId = proxy.mint(TEST_LABEL, user, IRegistry(address(0)), proxy.FLAG_SUBREGISTRY_LOCKED());

        // Deploy the upgrade implementation
        upgradeImplementation = new UserRegistryV2();

        // Upgrade the proxy
        vm.prank(owner);
        proxy.upgradeToAndCall(address(upgradeImplementation), "");

        // Cast to the new version
        UserRegistryV2 upgradedProxy = UserRegistryV2(address(proxy));

        // Verify all state is preserved
        assertEq(address(upgradedProxy.parent()), address(parentRegistry));
        assertEq(upgradedProxy.label(), PARENT_LABEL);
        assertEq(upgradedProxy.defaultDuration(), 365 days);

        // Verify tokens are preserved
        assertEq(upgradedProxy.ownerOf(tokenId), user);
        assertTrue(upgradedProxy.locked(tokenId));

        // Set version and create a new token with the new contract
        vm.prank(owner);
        upgradedProxy.upgradeToVersion(2);

        // Make sure parent registry will return owner when queried for mint
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(parentRegistry.ownerOf.selector, parentTokenId),
            abi.encode(owner)
        );

        vm.prank(owner);
        uint256 newTokenId = upgradedProxy.mint("upgraded", user, IRegistry(address(0)), 0);

        // Verify new token was created
        assertEq(upgradedProxy.ownerOf(newTokenId), user);

        // Ensure new function works
        assertEq(upgradedProxy.getTokenVersion(newTokenId), 2);
        assertEq(upgradedProxy.getTokenVersion(tokenId), 0); // Old token has version 0
    }

    function test_set_default_duration() public {
        // Make sure parent registry will return owner when queried
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(parentRegistry.ownerOf.selector, parentTokenId),
            abi.encode(owner)
        );

        uint64 newDuration = 2 * 365 days;

        // Set new default duration
        vm.prank(owner);
        proxy.setDefaultDuration(newDuration);

        // Verify duration was updated
        assertEq(proxy.defaultDuration(), newDuration);

        // Mint a name and check expiry uses new duration
        vm.prank(owner);
        uint256 tokenId = proxy.mint(TEST_LABEL, user, IRegistry(address(0)), 0);

        assertEq(proxy.getExpiry(tokenId), uint64(block.timestamp + newDuration));
    }

    function test_Revert_set_default_duration_not_owner() public {
        // Make sure parent registry will return owner when queried
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(parentRegistry.ownerOf.selector, parentTokenId),
            abi.encode(owner)
        );

        uint64 newDuration = 2 * 365 days;

        // Try to set duration as non-owner
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(BaseRegistry.AccessDenied.selector, 0, owner, user));
        proxy.setDefaultDuration(newDuration);
    }
}

// Extended version of UserRegistry for upgrade testing
contract UserRegistryV2 is UserRegistry {
    // New state variable - will be appended to storage layout
    uint256 public version;
    mapping(uint256 => uint256) private tokenVersions;

    function upgradeToVersion(uint256 newVersion) external onlyNameOwner {
        require(newVersion > version, "New version must be higher");
        version = newVersion;
    }

    // Override mint to set token version - using UserRegistry directly instead of super
    function mint(string calldata _label, address owner, IRegistry registry, uint96 flags)
        external
        override
        onlyNameOwner
        returns (uint256 tokenId)
    {
        tokenId = uint256(keccak256(bytes(_label)));

        // Set expiration for the name (default to 1 year)
        flags = (flags & FLAGS_MASK) | (uint96(uint64(block.timestamp + defaultDuration)) << 32);

        _mint(owner, tokenId, 1, "");
        datastore.setSubregistry(tokenId, address(registry), flags);

        emit NewSubname(_label);
        emit SubnameCreated(_label, owner, uint64(block.timestamp + defaultDuration));

        return tokenId;
    }

    function getTokenVersion(uint256 tokenId) external view returns (uint256) {
        return tokenVersions[tokenId];
    }
}
