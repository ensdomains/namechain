// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {SingleNameResolver} from "../../src/common/SingleNameResolver.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";
import {NameUtils} from "../../src/common/NameUtils.sol";

contract SingleNameResolverTest is Test {
    SingleNameResolver resolver;
    address owner = address(0x123);
    bytes32 testNode = 0xde9b09fd7c5f901e23a3f19fecc54828e9c848539801e86591bd9801b019f84f; // example.eth
    address testAddr = address(0x789);

    event AddrChanged(address addr);
    event AddressChanged(uint256 coinType, bytes newAddress);
    event TextChanged(string indexed key, string value);
    event ContenthashChanged(bytes hash);

    function setUp() public {
        // Deploy the resolver implementation
        SingleNameResolver implementation = new SingleNameResolver();

        // Deploy the factory
        VerifiableFactory factory = new VerifiableFactory();

        // Deploy the resolver proxy
        bytes memory initData = abi.encodeWithSelector(SingleNameResolver.initialize.selector, owner, testNode);

        uint256 salt = 123456; // Use a consistent salt for deterministic addresses
        address proxyAddress = factory.deployProxy(address(implementation), salt, initData);
        resolver = SingleNameResolver(proxyAddress);

        // Set up the test environment
        vm.startPrank(owner);
    }

    function testInitialization() public {
        assertEq(resolver.owner(), owner);
        assertEq(resolver.associatedName(), testNode);
    }

    function testSetAddr() public {
        // Record logs to verify events
        vm.recordLogs();

        // Set the address
        resolver.setAddr(testAddr);

        // Get the logs
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Verify events were emitted
        bool foundAddrChanged = false;
        bool foundAddressChanged = false;

        for (uint256 i = 0; i < logs.length; i++) {
            // Check for AddrChanged event
            if (logs[i].topics[0] == keccak256("AddrChanged(address)")) {
                foundAddrChanged = true;
                assertEq(abi.decode(logs[i].data, (address)), testAddr);
            }
            // Check for AddressChanged event
            else if (logs[i].topics[0] == keccak256("AddressChanged(uint256,bytes)")) {
                foundAddressChanged = true;
                (uint256 coinType, bytes memory addr) = abi.decode(logs[i].data, (uint256, bytes));
                assertEq(coinType, 60); // ETH coin type
                assertEq(bytesToAddress(addr), testAddr);
            }
        }

        assertTrue(foundAddrChanged, "AddrChanged event not emitted");
        assertTrue(foundAddressChanged, "AddressChanged event not emitted");

        // Verify the address was set correctly
        assertEq(resolver.addr(), testAddr);
    }

    function testSetAddrWithCoinType() public {
        uint256 coinType = 60; // ETH
        bytes memory addrBytes = addressToBytes(testAddr);

        // Record logs to verify events
        vm.recordLogs();

        // Set the address with coin type
        resolver.setAddr(coinType, addrBytes);

        // Get the logs
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Verify events were emitted
        bool foundAddrChanged = false;
        bool foundAddressChanged = false;

        for (uint256 i = 0; i < logs.length; i++) {
            // Check for AddrChanged event
            if (logs[i].topics[0] == keccak256("AddrChanged(address)")) {
                foundAddrChanged = true;
                assertEq(abi.decode(logs[i].data, (address)), testAddr);
            }
            // Check for AddressChanged event
            else if (logs[i].topics[0] == keccak256("AddressChanged(uint256,bytes)")) {
                foundAddressChanged = true;
                (uint256 coinType_, bytes memory addr) = abi.decode(logs[i].data, (uint256, bytes));
                assertEq(coinType_, coinType);
                assertEq(bytesToAddress(addr), testAddr);
            }
        }

        assertTrue(foundAddrChanged, "AddrChanged event not emitted");
        assertTrue(foundAddressChanged, "AddressChanged event not emitted");

        // Verify the address was set correctly
        assertEq(resolver.addr(), testAddr);
        assertEq(resolver.addr(coinType), addrBytes);
    }

    function testSetText() public {
        string memory key = "email";
        string memory value = "test@example.com";

        // Record logs to verify events
        vm.recordLogs();

        // Set the text record
        resolver.setText(key, value);

        // Get the logs
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Verify events were emitted
        bool foundTextChanged = false;

        for (uint256 i = 0; i < logs.length; i++) {
            // Check for TextChanged event
            if (logs[i].topics[0] == keccak256("TextChanged(string,string)")) {
                foundTextChanged = true;
                assertEq(logs[i].topics[1], keccak256(bytes(key)));
                assertEq(abi.decode(logs[i].data, (string)), value);
            }
        }

        assertTrue(foundTextChanged, "TextChanged event not emitted");

        // Verify the text record was set correctly
        assertEq(resolver.text(key), value);
    }

    function testSetContenthash() public {
        bytes memory hash = hex"1234567890";

        // Record logs to verify events
        vm.recordLogs();

        // Set the content hash
        resolver.setContenthash(hash);

        // Get the logs
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Verify events were emitted
        bool foundContenthashChanged = false;

        for (uint256 i = 0; i < logs.length; i++) {
            // Check for ContenthashChanged event
            if (logs[i].topics[0] == keccak256("ContenthashChanged(bytes)")) {
                foundContenthashChanged = true;
                assertEq(abi.decode(logs[i].data, (bytes)), hash);
            }
        }

        assertTrue(foundContenthashChanged, "ContenthashChanged event not emitted");

        // Verify the content hash was set correctly
        assertEq(resolver.contenthash(), hash);
    }

    function testAuthorization() public {
        // Set up a non-owner address
        address nonOwner = address(0xabc);

        // Stop pranking as owner
        vm.stopPrank();

        // Start pranking as non-owner
        vm.startPrank(nonOwner);

        // Should revert because caller is not authorized
        vm.expectRevert();
        resolver.setAddr(testAddr);

        // Should revert because caller is not the owner
        vm.expectRevert();
        resolver.setText("email", "test@example.com");

        // Should revert because caller is not the owner
        vm.expectRevert();
        resolver.setContenthash(hex"1234567890");
    }

    function testSupportsInterface() public {
        // Test for AddrResolver interface
        bytes4 addrResolverInterface = 0x3b3b57de;
        assertTrue(resolver.supportsInterface(addrResolverInterface));

        // Test for ERC165 interface
        bytes4 erc165Interface = 0x01ffc9a7;
        assertTrue(resolver.supportsInterface(erc165Interface));
    }

    // Helper functions
    function bytesToAddress(bytes memory b) internal pure returns (address payable a) {
        require(b.length == 20);
        assembly {
            a := div(mload(add(b, 32)), exp(256, 12))
        }
    }

    function addressToBytes(address a) internal pure returns (bytes memory b) {
        b = new bytes(20);
        assembly {
            mstore(add(b, 32), mul(a, exp(256, 12)))
        }
    }
}
