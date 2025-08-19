// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";
import {UUPSProxy} from "@ensdomains/verifiable-factory/UUPSProxy.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {RegistryDatastore} from "../src/common/RegistryDatastore.sol";
import {UserRegistry} from "../src/L2/UserRegistry.sol";
import {SimpleRegistryMetadata} from "../src/common/SimpleRegistryMetadata.sol";
import {IRegistryDatastore} from "../src/common/IRegistryDatastore.sol";
import {IRegistry} from "../src/common/IRegistry.sol";
import {IRegistryMetadata} from "../src/common/IRegistryMetadata.sol";
import {LibRegistryRoles} from "../src/common/LibRegistryRoles.sol";
import {NameUtils} from "../src/common/NameUtils.sol";
import {EnhancedAccessControl} from "../src/common/EnhancedAccessControl.sol";
import {IEnhancedAccessControl} from "../src/common/IEnhancedAccessControl.sol";
import {LibEACBaseRoles} from "../src/common/EnhancedAccessControl.sol";

contract UserRegistryTest is Test, ERC1155Holder {
    // Test constants
    uint256 constant SALT = 12345;
    uint256 constant ROOT_RESOURCE = 0;

    uint256 constant ROLE_UPGRADE = 1 << 20;
    uint256 constant ROLE_UPGRADE_ADMIN = ROLE_UPGRADE << 128;
    
    // Contracts
    VerifiableFactory factory;
    RegistryDatastore datastore;
    SimpleRegistryMetadata metadata;
    UserRegistry implementation;
    UserRegistry proxy;
    
    // Test accounts
    address admin = makeAddr("admin");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    
    function setUp() public {
        // Deploy the factory
        factory = new VerifiableFactory();
        
        // Deploy the datastore
        datastore = new RegistryDatastore();
        
        // Deploy metadata provider
        metadata = new SimpleRegistryMetadata();
        
        // Deploy the implementation
        implementation = new UserRegistry();
        
        // Create initialization data
        bytes memory initData = abi.encodeWithSelector(
            UserRegistry.initialize.selector,
            address(datastore),
            address(metadata),
            LibEACBaseRoles.ALL_ROLES,
            admin
        );
        
        // Deploy the proxy using the factory
        vm.prank(admin);
        address proxyAddress = factory.deployProxy(address(implementation), SALT, initData);
        
        // Get the proxy contract
        proxy = UserRegistry(proxyAddress);
    }

    function test_initialization() public view {
        // Verify the proxy was deployed correctly
        assertTrue(factory.verifyContract(address(proxy)), "Proxy should be verified");
        
        // Verify admin has the expected roles
        assertTrue(proxy.hasRootRoles(ROLE_UPGRADE, admin), "Admin should have upgrade role");
        assertTrue(proxy.hasRootRoles(ROLE_UPGRADE_ADMIN, admin), "Admin should have upgrade admin role");
        assertTrue(proxy.hasRootRoles(LibRegistryRoles.ROLE_REGISTRAR, admin), "Admin should have registrar role");
        
        // Verify other users don't have roles
        assertFalse(proxy.hasRootRoles(ROLE_UPGRADE, user1), "User1 should not have upgrade role");
        assertFalse(proxy.hasRootRoles(LibRegistryRoles.ROLE_REGISTRAR, user1), "User1 should not have registrar role");
        
        // Verify proxy returns the correct registry datastore
        assertEq(address(proxy.datastore()), address(datastore), "Datastore should match");
        
        // Verify proxy supports required interfaces
        assertTrue(proxy.supportsInterface(type(IRegistry).interfaceId), "Should support IRegistry");
        // UUPSUpgradeable doesn't have an interface ID, so we check for ERC1155 interface
        assertTrue(proxy.supportsInterface(0xd9b67a26), "Should support ERC1155");
    }
    
    function test_domain_registration() public {
        // Set up a domain name to register
        string memory label = "tanrikulu";
        
        // Register a domain as admin
        vm.prank(admin);
        uint256 tokenId = proxy.register(
            label,
            user1,
            IRegistry(address(0)),
            address(0),
            LibRegistryRoles.ROLE_SET_SUBREGISTRY | LibRegistryRoles.ROLE_SET_RESOLVER,
            uint64(block.timestamp + 365 days)
        );
        
        // Verify the domain was registered correctly
        assertEq(proxy.ownerOf(tokenId), user1, "Domain should be owned by user1");
        
        // Verify roles were granted to the owner
        assertTrue(proxy.hasRoles(tokenId, LibRegistryRoles.ROLE_SET_SUBREGISTRY, user1), "User1 should have SET_SUBREGISTRY role");
        assertTrue(proxy.hasRoles(tokenId, LibRegistryRoles.ROLE_SET_RESOLVER, user1), "User1 should have SET_RESOLVER role");
        
        // Verify the domain resolves correctly
        assertEq(address(proxy.getSubregistry(label)), address(0), "Subregistry should be zero address");
        assertEq(proxy.getResolver(label), address(0), "Resolver should be zero address");
    }
    
    function test_domain_management() public {
        // Register a domain
        vm.prank(admin);
        uint256 tokenId = proxy.register(
            "mdtdomain",
            user1,
            IRegistry(address(0)),
            address(0),
            LibRegistryRoles.ROLE_SET_SUBREGISTRY | LibRegistryRoles.ROLE_SET_RESOLVER,
            uint64(block.timestamp + 365 days)
        );
        
        // User1 sets a resolver
        address resolver = address(0x123);
        vm.prank(user1);
        proxy.setResolver(tokenId, resolver);
        
        // Verify resolver was set
        assertEq(proxy.getResolver("mdtdomain"), resolver, "Resolver should be set");
        
        // User1 sets a subregistry
        vm.prank(user1);
        proxy.setSubregistry(tokenId, IRegistry(address(0x456)));
        
        // Verify subregistry was set
        assertEq(address(proxy.getSubregistry("mdtdomain")), address(0x456), "Subregistry should be set");
    }
    
    function test_role_management() public {
        // Admin grants ROLE_REGISTRAR to user1
        vm.prank(admin);
        proxy.grantRootRoles(LibRegistryRoles.ROLE_REGISTRAR, user1);
        
        // Verify user1 has ROLE_REGISTRAR
        assertTrue(proxy.hasRootRoles(LibRegistryRoles.ROLE_REGISTRAR, user1), "User1 should have registrar role");
        
        // User1 should be able to register domains now
        vm.prank(user1);
        uint256 tokenId = proxy.register(
            "user1domain",
            user2,
            IRegistry(address(0)),
            address(0),
            LibRegistryRoles.ROLE_SET_SUBREGISTRY | LibRegistryRoles.ROLE_SET_RESOLVER,
            uint64(block.timestamp + 365 days)
        );
        
        // Verify registration was successful
        assertEq(proxy.ownerOf(tokenId), user2, "Domain should be owned by user2");
    }
    
    function test_Revert_unauthorized_registration() public {
        // User1 tries to register a domain without ROLE_REGISTRAR
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                ROOT_RESOURCE,
                LibRegistryRoles.ROLE_REGISTRAR,
                user1
            )
        );
        vm.prank(user1);
        proxy.register(
            "unauthorizeddomain",
            user1,
            IRegistry(address(0)),
            address(0),
            LibRegistryRoles.ROLE_SET_SUBREGISTRY | LibRegistryRoles.ROLE_SET_RESOLVER,
            uint64(block.timestamp + 365 days)
        );
    }
    
    function test_Revert_unauthorized_role_grant() public {
        // User1 tries to grant roles without permission
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACCannotGrantRoles.selector,
                ROOT_RESOURCE,
                LibRegistryRoles.ROLE_REGISTRAR,
                user1
            )
        );
        vm.prank(user1);
        proxy.grantRootRoles(LibRegistryRoles.ROLE_REGISTRAR, user2);
    }
    
    function testFuzz_domain_registration(string memory label, uint64 duration) public {
        // Skip empty labels and ensure reasonable duration
        vm.assume(bytes(label).length > 0);
        duration = uint64(bound(duration, 1 days, 10 * 365 days));
        
        uint64 expires = uint64(block.timestamp) + duration;
        
        // Register a domain as admin
        vm.prank(admin);
        uint256 tokenId = proxy.register(
            label,
            user1,
            IRegistry(address(0)),
            address(0),
            LibRegistryRoles.ROLE_SET_SUBREGISTRY | LibRegistryRoles.ROLE_SET_RESOLVER,
            expires
        );
        
        // Verify registration
        assertEq(proxy.ownerOf(tokenId), user1, "Domain should be owned by user1");
        assertEq(proxy.getExpiry(tokenId), expires, "Expiry should match");
    }
    
    // Test for contract upgradeability
    function test_upgrade() public {
        // Deploy a new implementation
        UserRegistryV2Mock newImplementation = new UserRegistryV2Mock();
        
        // Upgrade the proxy
        vm.prank(admin);
        proxy.upgradeToAndCall(address(newImplementation), "");
        
        // Test the new functionality
        UserRegistryV2Mock upgradedProxy = UserRegistryV2Mock(address(proxy));
        assertEq(upgradedProxy.version(), 2, "Version should be 2 after upgrade");
    }
    
    function test_Revert_unauthorized_upgrade() public {
        // Deploy a new implementation
        UserRegistryV2Mock newImplementation = new UserRegistryV2Mock();
        
        // User1 tries to upgrade without permission
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                ROOT_RESOURCE,
                ROLE_UPGRADE,
                user1
            )
        );
        vm.prank(user1);
        proxy.upgradeToAndCall(address(newImplementation), "");
    }
    
    function test_domain_expiration() public {
        // Register a domain with short expiry
        vm.prank(admin);
        uint256 tokenId = proxy.register(
            "expiredomain",
            user1,
            IRegistry(address(0)),
            address(0),
            LibRegistryRoles.ROLE_SET_SUBREGISTRY | LibRegistryRoles.ROLE_SET_RESOLVER,
            uint64(block.timestamp + 1 days)
        );
        
        // Verify it exists
        assertEq(proxy.ownerOf(tokenId), user1, "Domain should be owned by user1");
        
        // Advance time past expiration
        vm.warp(block.timestamp + 2 days);
        
        // Verify domain is expired
        assertEq(proxy.ownerOf(tokenId), address(0), "Expired domain should have no owner");
        assertEq(address(proxy.getSubregistry("expiredomain")), address(0), "Expired domain should have no subregistry");
        
        // Should be able to register it again
        vm.prank(admin);
        uint256 newTokenId = proxy.register(
            "expiredomain",
            user2,
            IRegistry(address(0)),
            address(0),
            LibRegistryRoles.ROLE_SET_SUBREGISTRY | LibRegistryRoles.ROLE_SET_RESOLVER,
            uint64(block.timestamp + 1 days)
        );
        
        // Verify new registration
        assertEq(proxy.ownerOf(newTokenId), user2, "Domain should be owned by user2");
    }


}

// Mock V2 contract for testing upgrades
contract UserRegistryV2Mock is UserRegistry {
    function version() public pure returns (uint256) {
        return 2;
    }
}
