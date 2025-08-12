// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ProxyLib} from "nexus/lib/ProxyLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IHCAFactory} from "./IHCAFactory.sol";
import {IHCA} from "./IHCA.sol";

contract HCAFactory is Ownable, IHCAFactory {
    address internal _implementation;

    event AccountCreated(address indexed owner, address indexed account);

    constructor(address implementation_, address owner_) Ownable(owner_) {
        _implementation = implementation_;
    }

    function setImplementation(address implementation_) external onlyOwner {
        _implementation = implementation_;
    }

    function createAccount(address owner_) external returns (address) {
        (bool alreadyDeployed, address payable account) = ProxyLib.deployProxy(
            _implementation,
            _getSalt(owner_),
            ""
        );
        if (!alreadyDeployed) emit AccountCreated(owner_, account);
        return account;
    }

    function getImplementation() external view returns (address) {
        return _implementation;
    }

    function getAccountOwner(address account) external view returns (address) {
        try IHCA(account).getOwner() returns (address owner) {
            return owner;
        } catch {
            return address(0);
        }
    }

    function computeAccountAddress(
        address owner_
    ) external view returns (address) {
        return
            ProxyLib.predictProxyAddress(_implementation, _getSalt(owner_), "");
    }

    function _getSalt(address owner_) internal pure returns (bytes32) {
        return bytes32(bytes20(owner_));
    }
}
