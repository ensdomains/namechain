// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {AddrResolver} from "@ens/contracts/resolvers/profiles/AddrResolver.sol";
import {ABIResolver} from "@ens/contracts/resolvers/profiles/ABIResolver.sol";
import {ContentHashResolver} from "@ens/contracts/resolvers/profiles/ContentHashResolver.sol";
import {DNSResolver} from "@ens/contracts/resolvers/profiles/DNSResolver.sol";
import {InterfaceResolver} from "@ens/contracts/resolvers/profiles/InterfaceResolver.sol";
import {NameResolver} from "@ens/contracts/resolvers/profiles/NameResolver.sol";
import {PubkeyResolver} from "@ens/contracts/resolvers/profiles/PubkeyResolver.sol";
import {TextResolver} from "@ens/contracts/resolvers/profiles/TextResolver.sol";
import {Multicallable} from "@ens/contracts/resolvers/Multicallable.sol";

/**
 * @title OwnedResolver
 * @dev A simple resolver anyone can use; only allows the owner of a node to set its
 * address.
 */
contract OwnedResolver is
    OwnableUpgradeable,
    UUPSUpgradeable,
    ABIResolver,
    AddrResolver,
    ContentHashResolver,
    DNSResolver,
    InterfaceResolver,
    NameResolver,
    PubkeyResolver,
    TextResolver,
    Multicallable
{
    function initialize(address _owner) public initializer {
        __Ownable_init(_owner); // Initialize Ownable
        __UUPSUpgradeable_init();
    }

    function isAuthorised(bytes32) internal view override returns (bool) {
        return msg.sender == owner();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

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
            TextResolver,
            Multicallable
        )
        returns (bool)
    {
        return super.supportsInterface(interfaceID);
    }
}
