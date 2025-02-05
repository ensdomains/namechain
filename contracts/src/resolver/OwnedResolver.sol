// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {AddrResolver} from "@ens/contracts/resolvers/profiles/AddrResolver.sol";
import {ABIResolver} from "@ens/contracts/resolvers/profiles/ABIResolver.sol";
import {ContentHashResolver} from "@ens/contracts/resolvers/profiles/ContentHashResolver.sol";
import {DNSResolver} from "@ens/contracts/resolvers/profiles/DNSResolver.sol";
import {InterfaceResolver} from "@ens/contracts/resolvers/profiles/InterfaceResolver.sol";
import {NameResolver} from "@ens/contracts/resolvers/profiles/NameResolver.sol";
import {PubkeyResolver} from "@ens/contracts/resolvers/profiles/PubkeyResolver.sol";
import {TextResolver} from "@ens/contracts/resolvers/profiles/TextResolver.sol";
import {ExtendedResolver} from "@ens/contracts/resolvers/profiles/ExtendedResolver.sol";

/**
 * @title OwnedResolver
 * @dev A basic resolver contract with ownership functionality
 */
contract OwnedResolver is
    OwnableUpgradeable,
    ABIResolver,
    AddrResolver,
    ContentHashResolver,
    DNSResolver,
    InterfaceResolver,
    NameResolver,
    PubkeyResolver,
    TextResolver,
    ExtendedResolver
    {

    function initialize(address _owner) public initializer {
        __Ownable_init(_owner); // Initialize Ownable
    }

    function isAuthorised(bytes32) internal view override returns (bool) {
        return msg.sender == owner();
    }
    function supportsInterface(
        bytes4 interfaceID
    )
        public
        view
        virtual
        override(
            ABIResolver,
            AddrResolver,
            ContentHashResolver,
            DNSResolver,
            InterfaceResolver,
            NameResolver,
            PubkeyResolver,
            TextResolver
        )
        returns (bool)
    {
        return super.supportsInterface(interfaceID);
    }

} 