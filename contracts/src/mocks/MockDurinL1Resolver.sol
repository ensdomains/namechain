// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MockDurinL2Registry} from "./MockDurinL2Registry.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
contract MockDurinL1Resolver is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {

    }

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct L2Registry {
        uint64 chainId;
        address registryAddress;
    }

    mapping(bytes32 node => L2Registry l2Registry) public l2Registry;
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(bytes memory _name, uint256 _chainId, address _l2Registry) public initializer {
        emit MetadataChanged(_name, "https://graphql.eth.link", _chainId, _l2Registry);
    }

    /// @notice Emitted when the metadata is changed for a given name.
    /// @param name The name that the metadata is changed for.
    /// @param graphqlUrl The graphql url for the given name.
    /// @param chainId The chain id for the given name.
    /// @param l2RegistryAddress The l2 registry address for the given name.
    /// @dev This is a mock event for testing purposes. 
    event MetadataChanged(
        bytes name,
        string graphqlUrl,
        uint256 chainId,
        address l2RegistryAddress
    );

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Specify the L2 registry for a given name. Should only be used with 2LDs, e.g. "nick.eth".
    /// @dev Only callable by the contract owner.
    function setL2Registry(
        bytes calldata name,
        string memory graphqlUrl,
        uint256 chainId,
        address l2RegistryAddress
    ) external {
        emit MetadataChanged(name, graphqlUrl, chainId, l2RegistryAddress);
    }
} 