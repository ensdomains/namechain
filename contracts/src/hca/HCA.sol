// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Nexus} from "nexus/Nexus.sol";

import {IHCAFactory} from "./IHCAFactory.sol";
import {IK1Validator} from "./IK1Validator.sol";

contract HCA is Nexus {
    IHCAFactory private immutable _HCA_FACTORY;

    error HCAFactoryCannotBeZero();

    error CallerNotHCAFactory();

    error UninstallModuleNotAllowed();

    modifier onlyHCAFactory() {
        if (msg.sender != address(_HCA_FACTORY)) revert CallerNotHCAFactory();
        _;
    }

    constructor(
        IHCAFactory hcaFactory_,
        address entryPoint_,
        address defaultValidator_,
        bytes memory initData_
    ) Nexus(entryPoint_, defaultValidator_, initData_) {
        if (address(hcaFactory_) == address(0)) revert HCAFactoryCannotBeZero();
        _HCA_FACTORY = hcaFactory_;
    }

    fallback() external payable {
        bytes32 s;
        // don't allow 721/1155 transfers
        /// @solidity memory-safe-assembly
        assembly {
            s := shr(224, calldataload(0))
            // 0x150b7a02: `onERC721Received(address,address,uint256,bytes)`.
            // 0xf23a6e61: `onERC1155Received(address,address,uint256,uint256,bytes)`.
            // 0xbc197c81: `onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)`.
            if or(eq(s, 0x150b7a02), or(eq(s, 0xf23a6e61), eq(s, 0xbc197c81))) {
                mstore(0x20, s) // Store `msg.sig`.
                revert(0, 0)
            }
        }
        _fallback(msg.data);
    }

    function installModule(
        uint256 moduleTypeId,
        address module,
        bytes calldata initData
    ) external payable override {
        if (isInitialized()) revert AccountAlreadyInitialized();
        super.installModule(moduleTypeId, module, initData);
    }

    function uninstallModule(
        uint256 /* moduleTypeId */,
        address /* module */,
        bytes calldata /* deInitData */
    ) external payable override {
        revert UninstallModuleNotAllowed();
    }

    function getOwner() external view returns (address) {
        // we will only ever use the default validator
        return IK1Validator(_DEFAULT_VALIDATOR).getOwner(address(this));
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyHCAFactory {
        super._authorizeUpgrade(newImplementation);
    }
}
