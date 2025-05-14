// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IRegistry} from "../../src/common/IRegistry.sol";
import {IERC1155Singleton} from "../../src/common/IERC1155Singleton.sol";

/**
 * @title MockRegistry
 * @dev A mock implementation of IRegistry for testing purposes
 */
contract MockRegistry is IRegistry {
    mapping(string => address) private subregistries;
    mapping(string => address) private resolvers;

    function setSubregistry(string memory label, address subregistry) external {
        subregistries[label] = subregistry;
    }

    function setResolver(string memory label, address resolver) external {
        resolvers[label] = resolver;
    }

    function getSubregistry(string calldata label) external view override returns (IRegistry) {
        return IRegistry(subregistries[label]);
    }

    function getResolver(string calldata label) external view override returns (address) {
        return resolvers[label];
    }

    // IERC1155Singleton implementation
    function balanceOf(address, uint256) external pure override returns (uint256) {
        return 1;
    }

    function balanceOfBatch(address[] calldata, uint256[] calldata) external pure override returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](1);
        balances[0] = 1;
        return balances;
    }

    function safeTransferFrom(address, address, uint256, uint256, bytes calldata) external pure override {
        // Do nothing
    }

    function safeBatchTransferFrom(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external pure override {
        // Do nothing
    }

    function setApprovalForAll(address, bool) external pure override {
        // Do nothing
    }

    function isApprovedForAll(address, address) external pure override returns (bool) {
        return true;
    }

    function ownerOf(uint256) external pure override returns (address) {
        return address(0x123);
    }

    function supportsInterface(bytes4) external pure override returns (bool) {
        return true;
    }
}
