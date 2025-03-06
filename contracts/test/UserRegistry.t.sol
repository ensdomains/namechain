// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IAccessControl} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

import "../src/registry/RegistryDatastore.sol";
import "../src/registry/ETHRegistry.sol";
import "../src/registry/UserRegistry.sol";
import "../src/registry/IRegistry.sol";
import "../src/registry/ERC1155SingletonUpgradable.sol";
import "verifiable-factory/VerifiableFactory.sol";

contract TestUserRegistry is Test, ERC1155Holder {
    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );
    event NewSubname(string label);

    RegistryDatastore datastore;
    ETHRegistry parentRegistry;
    UserRegistry implementation;
    UserRegistry proxy;
    UserRegistryV2 upgradeImplementation;
    VerifiableFactory factory;
    address owner = address(1);
    address user = address(3);
    uint256 salt = 123456;

    uint256 parentTokenId;
    string constant PARENT_LABEL = "eth";
    string constant TEST_LABEL = "test";

    function setUp() public {
        // Deploy base contracts
        datastore = new RegistryDatastore();
        parentRegistry = new ETHRegistry(datastore);
        parentRegistry.grantRole(
            parentRegistry.REGISTRAR_ROLE(),
            address(this)
        );

        // Register parent name - make sure the owner is correctly set
        parentTokenId = parentRegistry.register(
            PARENT_LABEL,
            owner,
            parentRegistry,
            0,
            uint64(block.timestamp) + 365 days
        );

        // Verify the owner of the parent name
        assertEq(parentRegistry.ownerOf(parentTokenId), owner);

        // Deploy implementation & proxy
        implementation = new UserRegistry();
        factory = new VerifiableFactory();

        // Encode initialization data
        bytes memory initData = abi.encodeWithSelector(
            UserRegistry.initialize.selector,
            datastore,
            parentRegistry,
            PARENT_LABEL,
            owner
        );

        // Deploy proxy using VerifiableFactory
        address proxyAddress = factory.deployProxy(
            address(implementation),
            salt,
            initData
        );

        // Cast proxy to UserRegistry type
        proxy = UserRegistry(proxyAddress);
    }

    // =================== Basic Functionality Tests ===================

    function test_initialization() public view {
        assertEq(address(proxy.parent()), address(parentRegistry));
        assertEq(proxy.label(), PARENT_LABEL);

        // Check roles
        assertTrue(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), owner));
    }

    function test_mint_subname() public {
        // Make sure parent registry will return owner when queried
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(
                parentRegistry.ownerOf.selector,
                parentTokenId
            ),
            abi.encode(owner)
        );

        // Owner should be able to mint a subname
        vm.prank(owner);

        uint256 tokenId = proxy.mint(
            TEST_LABEL,
            user,
            IRegistry(address(0)),
            0
        );

        // Verify token was created
        assertEq(proxy.ownerOf(tokenId), user);
    }

    function test_mint_subname_emits_event() public {
        // Make sure parent registry will return owner when queried
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(
                parentRegistry.ownerOf.selector,
                parentTokenId
            ),
            abi.encode(owner)
        );

        vm.startPrank(owner);

        vm.recordLogs();
        proxy.mint(TEST_LABEL, user, IRegistry(address(0)), 0);

        vm.stopPrank();

        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Should emit NewSubname event
        bool foundNewSubname = false;

        for (uint256 i = 0; i < entries.length; i++) {
            // Check for NewSubname event
            if (entries[i].topics[0] == keccak256("NewSubname(string)")) {
                foundNewSubname = true;
            }
        }

        assertTrue(foundNewSubname);
    }

    function test_Revert_mint_not_owner() public {
        // Make sure parent registry will return owner when queried
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(
                parentRegistry.ownerOf.selector,
                parentTokenId
            ),
            abi.encode(owner)
        );

        // Non-owner should not be able to mint
        vm.prank(user);

        vm.expectRevert(
            abi.encodeWithSelector(
                UserRegistry.AccessDenied.selector,
                0,
                owner,
                user
            )
        );
        proxy.mint(TEST_LABEL, user, IRegistry(address(0)), 0);
    }

    function test_burn_subname() public {
        // Make sure parent registry will return owner when queried
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(
                parentRegistry.ownerOf.selector,
                parentTokenId
            ),
            abi.encode(owner)
        );

        // First mint a subname
        vm.prank(owner);
        uint256 tokenId = proxy.mint(
            TEST_LABEL,
            owner,
            IRegistry(address(0)),
            0
        );

        // Now burn it
        vm.prank(owner);
        proxy.burn(tokenId);

        // Verify token was burned
        assertEq(proxy.ownerOf(tokenId), address(0));
    }

    function test_Revert_burn_locked_subname() public {
        // Mock the correct tokenId for the parent registry's ownerOf call
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(
                parentRegistry.ownerOf.selector,
                parentTokenId
            ),
            abi.encode(owner)
        );

        // Mint a subname with locked subregistry
        vm.prank(owner);
        uint256 tokenId = proxy.mint(
            TEST_LABEL,
            owner,
            IRegistry(address(0)),
            proxy.FLAG_SUBREGISTRY_LOCKED()
        );

        // Try to burn it
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                UserRegistry.InvalidSubregistryFlags.selector,
                tokenId,
                proxy.FLAG_SUBREGISTRY_LOCKED(),
                0
            )
        );
        proxy.burn(tokenId);
    }

    // =================== Lock Tests ===================

    function test_lock_subregistry() public {
        // Make sure parent registry will return owner when queried
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(
                parentRegistry.ownerOf.selector,
                parentTokenId
            ),
            abi.encode(owner)
        );

        // First mint a subname
        vm.prank(owner);
        uint256 tokenId = proxy.mint(
            TEST_LABEL,
            user,
            IRegistry(address(0)),
            0
        );

        // Lock it
        vm.prank(user);
        proxy.lockSubregistry(tokenId);

        // Get flags to verify it's locked
        (, uint96 flags) = datastore.getSubregistry(tokenId);
        assertTrue(flags & proxy.FLAG_SUBREGISTRY_LOCKED() != 0);
    }

    function test_lockResolver_subname() public {
        // Make sure parent registry will return owner when queried
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(
                parentRegistry.ownerOf.selector,
                parentTokenId
            ),
            abi.encode(owner)
        );

        // First mint a subname
        vm.prank(owner);
        uint256 tokenId = proxy.mint(
            TEST_LABEL,
            user,
            IRegistry(address(0)),
            0
        );

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
                UserRegistry.InvalidSubregistryFlags.selector,
                tokenId,
                proxy.FLAG_RESOLVER_LOCKED(),
                0
            )
        );
        proxy.setResolver(tokenId, address(2));
    }

    function test_lockFlags_subname() public {
        // Make sure parent registry will return owner when queried
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(
                parentRegistry.ownerOf.selector,
                parentTokenId
            ),
            abi.encode(owner)
        );

        // First mint a subname
        vm.prank(owner);
        uint256 tokenId = proxy.mint(
            TEST_LABEL,
            user,
            IRegistry(address(0)),
            0
        );

        // Lock flags
        vm.prank(user);
        proxy.lockFlags(tokenId);

        // Try to set flags - Fixed order of operations
        vm.expectRevert(
            abi.encodeWithSelector(UserRegistry.InvalidSubregistryFlags.selector, tokenId, proxy.FLAG_FLAGS_LOCKED(), 0)
        );
        vm.prank(user);
        proxy.setFlags(tokenId, proxy.FLAG_SUBREGISTRY_LOCKED());
    }

    // =================== Upgrade Tests ===================

    function test_upgrade() public {
        // Deploy the upgrade implementation
        upgradeImplementation = new UserRegistryV2();

        // Get ERC1967 implementation slot to check implementation address
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address currentImplementation = address(
            uint160(uint256(vm.load(address(proxy), implementationSlot)))
        );
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

        // Make sure parent registry will return owner when queried for upgradeToVersion
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(
                parentRegistry.ownerOf.selector,
                parentTokenId
            ),
            abi.encode(owner)
        );

        // Call the upgrade function to set version
        vm.prank(owner);
        upgradedProxy.upgradeToVersion(2);

        // Verify version was updated
        assertEq(upgradedProxy.version(), 2);

        // Verify implementation address changed
        address newImplementation = address(
            uint160(uint256(vm.load(address(proxy), implementationSlot)))
        );
        assertEq(newImplementation, address(upgradeImplementation));
    }

    function test_Revert_upgrade_not_authorized() public {
        // Deploy the upgrade implementation
        upgradeImplementation = new UserRegistryV2();

        // Attempt unauthorized upgrade
        vm.prank(user); // Not the owner
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                proxy.DEFAULT_ADMIN_ROLE()
            )
        );
        proxy.upgradeToAndCall(address(upgradeImplementation), "");
    }

    function test_storage_integrity_after_upgrade() public {
        // Make sure parent registry will return owner when queried
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(
                parentRegistry.ownerOf.selector,
                parentTokenId
            ),
            abi.encode(owner)
        );

        // First mint a subname
        vm.prank(owner);
        uint256 tokenId = proxy.mint(
            TEST_LABEL,
            user,
            IRegistry(address(0)),
            proxy.FLAG_SUBREGISTRY_LOCKED()
        );

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

        // Verify tokens are preserved
        assertEq(upgradedProxy.ownerOf(tokenId), user);
        // Check if it's locked by directly querying datastore
        (, uint96 flags) = datastore.getSubregistry(tokenId);
        assertTrue((flags & proxy.FLAG_SUBREGISTRY_LOCKED()) != 0);

        // Set version and create a new token with the new contract
        vm.prank(owner);
        upgradedProxy.upgradeToVersion(2);

        // Make sure parent registry will return owner when queried for mint
        vm.mockCall(
            address(parentRegistry),
            abi.encodeWithSelector(
                parentRegistry.ownerOf.selector,
                parentTokenId
            ),
            abi.encode(owner)
        );

        vm.prank(owner);
        uint256 newTokenId = upgradedProxy.mint(
            "upgraded",
            user,
            IRegistry(address(0)),
            0
        );

        // Verify new token was created
        assertEq(upgradedProxy.ownerOf(newTokenId), user);

        // Ensure new function works
        assertEq(upgradedProxy.getTokenVersion(newTokenId), 2);
        assertEq(upgradedProxy.getTokenVersion(tokenId), 0); // Old token has version 0
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

    // Override mint to set token version
    function mint(
        string calldata sublabel,
        address owner,
        IRegistry registry,
        uint96 flags
    ) external override onlyNameOwner returns (uint256 tokenId) {
        tokenId = uint256(keccak256(bytes(sublabel)));

        // Apply flags to the lowest bits of the token ID
        tokenId = (tokenId & ~uint256(FLAGS_MASK)) | (flags & FLAGS_MASK);

        // Create the token and set its registry
        _mint(owner, tokenId, 1, "");
        datastore.setSubregistry(tokenId, address(registry), flags);

        // Set the token version - this is the new functionality
        tokenVersions[tokenId] = version;

        emit NewSubname(sublabel);

        return tokenId;
    }

    function getTokenVersion(uint256 tokenId) external view returns (uint256) {
        return tokenVersions[tokenId];
    }
}
