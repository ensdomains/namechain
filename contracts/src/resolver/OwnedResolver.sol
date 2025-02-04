// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";

/**
 * @title OwnedResolver
 * @dev A basic resolver contract with ownership functionality
 */
contract OwnedResolver {
    mapping(bytes32 => uint64) public recordVersions;
    mapping(uint64 => mapping(bytes32 => mapping(uint256 => bytes))) versionable_addresses;

    modifier authorised(bytes32 node) {
        require(isAuthorised(node));
        _;
    }

    function msgSender() public view returns (address) {
        console.log("msg.sender:", msg.sender);
        console.log("owner:", owner());
        return msg.sender;
    }

    function isAuthorised(bytes32) internal view returns (bool) {
        console.log("isAuthorised:", msg.sender == owner());
        console.log("msg.sender:", msg.sender);
        console.log("owner:", owner());
        return msg.sender == owner();
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