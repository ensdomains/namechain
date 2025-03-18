// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ERC1155SingletonBase} from "./ERC1155SingletonBase.sol";

/**
 * @title ERC1155SingletonUpgradeable
 * @dev Upgradeable implementation of the ERC1155SingletonBase contract.
 * This provides concrete implementations of the abstract functions defined in the base,
 * with proper upgrade-safe patterns.
 */
abstract contract ERC1155SingletonUpgradeable is 
    Initializable, 
    ContextUpgradeable, 
    ERC165Upgradeable, 
    ERC1155SingletonBase 
{
    // Storage gap for future upgrades
    uint256[49] private __gap;
    
    /**
     * @dev Initializes the contract by setting the initial parameters.
     */
    function __ERC1155Singleton_init() internal onlyInitializing {
        __Context_init_unchained();
        __ERC165_init_unchained();
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        virtual 
        override(ERC165Upgradeable, ERC1155SingletonBase) 
        returns (bool) 
    {
        return ERC1155SingletonBase.supportsInterface(interfaceId) || ERC165Upgradeable.supportsInterface(interfaceId);
    }

    /**
     * @dev Gets the sender of the current context.
     */
    function _msgSender() internal view virtual override(ContextUpgradeable, ERC1155SingletonBase) returns (address) {
        return ContextUpgradeable._msgSender();
    }
}
