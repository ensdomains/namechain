// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {AddrResolver} from "@ens/contracts/resolvers/profiles/AddrResolver.sol";
/**
 * @title OwnedResolver
 * @dev A basic resolver contract with ownership functionality
 */
contract OwnedResolver is OwnableUpgradeable, AddrResolver {

    function initialize(address _owner) public initializer {
        __Ownable_init(_owner); // Initialize Ownable
    }

    function isAuthorised(bytes32) internal view override returns (bool) {
        return msg.sender == owner();
    }

} 