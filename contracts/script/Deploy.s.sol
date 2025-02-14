// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {RegistryDatastore} from "../src/registry/RegistryDatastore.sol";
import {IRegistryDatastore} from "../src/registry/IRegistryDatastore.sol";
import {IRegistry} from "../src/registry/IRegistry.sol";
import {RootRegistry} from "../src/registry/RootRegistry.sol";
import {ETHRegistry} from "../src/registry/ETHRegistry.sol";
import {UniversalResolver} from "../src/utils/UniversalResolver.sol";
import {OwnedResolver} from "../src/resolver/OwnedResolver.sol";
import {VerifiableFactory} from "verifiable-factory/VerifiableFactory.sol";

contract DeployScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("deployer", deployer);
        vm.startBroadcast(deployerPrivateKey);

        // Deploy RegistryDatastore
        RegistryDatastore datastore = new RegistryDatastore();
        console.log("RegistryDatastore deployed to:", address(datastore));

        // Deploy RootRegistry
        RootRegistry rootRegistry = new RootRegistry(IRegistryDatastore(address(datastore)));
        console.log("RootRegistry deployed to:", address(rootRegistry));

        // Deploy ETHRegistry
        ETHRegistry ethRegistry = new ETHRegistry(IRegistryDatastore(address(datastore)));
        console.log("ETHRegistry deployed to:", address(ethRegistry));

        // Deploy UniversalResolver
        UniversalResolver universalResolver = new UniversalResolver(IRegistry(address(rootRegistry)));
        console.log("UniversalResolver deployed to:", address(universalResolver));

        // Deploy OwnedResolver implementation
        OwnedResolver resolverImplementation = new OwnedResolver();
        console.log("OwnedResolver implementation deployed to:", address(resolverImplementation));

        // Deploy VerifiableFactory
        VerifiableFactory factory = new VerifiableFactory();
        console.log("VerifiableFactory deployed to:", address(factory));

    //     // Deploy resolver proxy
    //     bytes memory initData = abi.encodeWithSelector(
    //         OwnedResolver.initialize.selector,
    //         deployer
    //     );
    //     console.log("deployer", deployer);
    //     uint256 SALT = 12345;
    //     address resolverAddress = factory.deployProxy(
    //         address(resolverImplementation),
    //         SALT,
    //         initData
    //     );
    //     console.log("OwnedResolver proxy deployed to:", resolverAddress);
    //     bytes32 tldrole = rootRegistry.TLD_ISSUER_ROLE();
    //     console.logBytes32(tldrole);
    //     rootRegistry.grantRole(tldrole, deployer);
    //     console.log("Granted TLD_ISSUER_ROLE to deployer");
    //     console.log("hasRole", rootRegistry.hasRole(tldrole, deployer));
    //     ethRegistry.grantRole(ethRegistry.REGISTRAR_ROLE(), deployer);
    //     console.log("Granted REGISTRAR_ROLE to deployer");

    //     // Mint .eth TLD
    //     rootRegistry.mint(
    //         "eth",
    //         deployer,
    //         IRegistry(address(ethRegistry)),
    //         1,
    //         "https://example.com/"
    //     );
    //     console.log("Minted .eth TLD");
    //     // Register test.eth
    //     string memory testName = "test";
    //     uint64 expires = uint64(block.timestamp + 365 days);
    //     ethRegistry.register(
    //         testName,
    //         deployer,
    //         IRegistry(address(ethRegistry)),
    //         0,
    //         expires
    //     );
    //     console.log("Registered test.eth");
    //     // Set resolver for test.eth
    //     bytes32 testLabelHash = keccak256(bytes(testName));
    //     ethRegistry.setResolver(uint256(testLabelHash), resolverAddress);
    //     console.log("Set resolver for test.eth");
    //     // Set ETH address for test.eth
    //     OwnedResolver(resolverAddress).setAddr(
    //         bytes32(testLabelHash),
    //         60, // ETH coin type
    //         abi.encodePacked(deployer)
    //     );
    //     console.log("Set ETH address for test.eth");
    //     vm.stopBroadcast();

    //     // Verify contracts
    //     if (block.chainid != 31337) { // Skip verification on local chain
            verify(address(datastore), "RegistryDatastore", "");
            console.log("Verified RegistryDatastore");
            verify(address(rootRegistry), "RootRegistry", vm.toString(address(datastore)));
            verify(address(ethRegistry), "ETHRegistry", vm.toString(address(datastore)));
            verify(address(universalResolver), "UniversalResolver", vm.toString(address(rootRegistry)));
            verify(address(resolverImplementation), "OwnedResolver", "");
            verify(address(factory), "VerifiableFactory", "");
    //     }
    }

    function verify(address addr, string memory name, string memory args) internal {
        string[] memory inputs;
        if (bytes(args).length > 0) {
            inputs = new string[](8);
            inputs[0] = "forge";
            inputs[1] = "verify-contract";
            inputs[2] = vm.toString(addr);
            inputs[3] = name;
            inputs[4] = "--chain";
            inputs[5] = "sepolia";
            inputs[6] = "--constructor-args";
            inputs[7] = args;
        } else {
            inputs = new string[](6);
            inputs[0] = "forge";
            inputs[1] = "verify-contract";
            inputs[2] = vm.toString(addr);
            inputs[3] = name;
            inputs[4] = "--chain";
            inputs[5] = "sepolia";
        }
        vm.ffi(inputs);
    }
} 