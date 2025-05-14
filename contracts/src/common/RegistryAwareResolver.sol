// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";

import {ResolverBase} from "@ens/contracts/resolvers/ResolverBase.sol";
import {AddrResolver} from "@ens/contracts/resolvers/profiles/AddrResolver.sol";
import {ABIResolver} from "@ens/contracts/resolvers/profiles/ABIResolver.sol";
import {ContentHashResolver} from "@ens/contracts/resolvers/profiles/ContentHashResolver.sol";
import {DNSResolver} from "@ens/contracts/resolvers/profiles/DNSResolver.sol";
import {InterfaceResolver} from "@ens/contracts/resolvers/profiles/InterfaceResolver.sol";
import {NameResolver} from "@ens/contracts/resolvers/profiles/NameResolver.sol";
import {PubkeyResolver} from "@ens/contracts/resolvers/profiles/PubkeyResolver.sol";
import {TextResolver} from "@ens/contracts/resolvers/profiles/TextResolver.sol";
import {ExtendedResolver} from "@ens/contracts/resolvers/profiles/ExtendedResolver.sol";
import {Multicallable} from "@ens/contracts/resolvers/Multicallable.sol";
import {NameUtils} from "./NameUtils.sol";
import {IRegistry} from "./IRegistry.sol";

/**
 * @title RegistryAwareResolver
 * @dev A resolver that leverages registry-level aliasing instead of implementing aliasing at the resolver level.
 * This resolver is aware of the registry structure and properly handles namehash and labelhash according to ENS standards.
 */
contract RegistryAwareResolver is
    OwnableUpgradeable,
    UUPSUpgradeable,
    ResolverBase,
    ABIResolver,
    AddrResolver,
    ContentHashResolver,
    DNSResolver,
    InterfaceResolver,
    NameResolver,
    PubkeyResolver,
    TextResolver,
    ExtendedResolver,
    Multicallable
{
    // Registry this resolver is associated with
    IRegistry public registry;
    
    // Coin type for ETH
    uint256 private constant COIN_TYPE_ETH = 60;

    /**
     * @dev Initializes the resolver with an owner and registry
     * @param _owner The owner of the resolver
     * @param _registry The registry this resolver is associated with
     */
    function initialize(address _owner, IRegistry _registry) public initializer {
        __Ownable_init(_owner); // Initialize Ownable
        __UUPSUpgradeable_init();
        registry = _registry;
    }

    /**
     * @dev Checks if the sender is authorized to modify records
     * @return Whether the sender is authorized
     */
    function isAuthorised(bytes32) internal view override returns (bool) {
        return msg.sender == owner();
    }
    
    /**
     * @dev Authorizes an upgrade to the implementation
     * @param newImplementation The new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function supportsInterface(
        bytes4 interfaceID
    )
        public
        view
        virtual
        override(
            ResolverBase,
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

    /**
     * @dev Sets the address for a node, ensuring proper event emission
     * @param node The namehash of the node
     * @param a The address to set
     */
    function setAddr(bytes32 node, address a) external override authorised(node) {
        // Convert the address to bytes and call the parent implementation with ETH coin type
        bytes memory addrBytes = addressToBytes(a);
        super.setAddr(node, COIN_TYPE_ETH, addrBytes);
        
        // The parent implementation already emits the AddressChanged event
        // We need to explicitly emit the AddrChanged event
        emit AddrChanged(node, a);
    }

    /**
     * @dev Sets the address for a node with a specific coin type, ensuring proper event emission
     * @param node The namehash of the node
     * @param coinType The coin type to set
     * @param a The address to set
     */
    function setAddr(bytes32 node, uint256 coinType, bytes memory a) public override authorised(node) {
        // Call the parent implementation to set the address
        super.setAddr(node, coinType, a);
        
        // The parent implementation already emits the AddressChanged event
        // and the AddrChanged event for ETH addresses
    }
}
