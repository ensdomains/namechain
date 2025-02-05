// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
/**
 * @title OwnedResolver
 * @dev A basic resolver contract with ownership functionality
 */
contract OwnedResolver is OwnableUpgradeable {
    mapping(bytes32 => uint64) public recordVersions;
    mapping(uint64 => mapping(bytes32 => mapping(uint256 => bytes))) versionable_addresses;

    function initialize(address _owner) public initializer {
        __Ownable_init(_owner); // Initialize Ownable
    }

    function isAuthorised(bytes32) internal view returns (bool) {
        return msg.sender == owner();
    }

    modifier authorised(bytes32 node) {
        require(isAuthorised(node));
        _;
    }


    function setAddr(
        bytes32 node,
        uint256 coinType,
        bytes memory a
    ) public virtual authorised(node) {
        versionable_addresses[recordVersions[node]][node][coinType] = a;
    }

    function addr(
        bytes32 node,
        uint256 coinType
    ) public view returns (bytes memory) {
        return versionable_addresses[recordVersions[node]][node][coinType];
    }

} 