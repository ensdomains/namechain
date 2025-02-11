// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IETHRegistrar} from "./IETHRegistrar.sol";
import {IRegistry} from "./IRegistry.sol";
import {IERC1155Singleton} from "./IERC1155Singleton.sol";
import {IETHRegistry} from "./IETHRegistry.sol";

contract ETHRegistrar is IETHRegistrar {
    IETHRegistry public registry;
    mapping(address => bool) public controllers;
    mapping(uint256 => bool) public registered;

    constructor(address _registry) {
        registry = IETHRegistry(_registry);
    }
    
    modifier onlyController() {
        require(controllers[msg.sender], "ETHRegistrar: not controller");
        _;
    }

    function addController(address controller) external {
        require(controller != address(0), "ETHRegistrar: zero address");
        controllers[controller] = true;
        emit ControllerAdded(controller);
    }

    function removeController(address controller) external {
        controllers[controller] = false;
        emit ControllerRemoved(controller);
    }

    function available(uint256 tokenId) external view returns (bool) {
        (uint64 expiry, ) = registry.nameData(tokenId);
        return expiry < block.timestamp;
    }

    function register(
        string calldata label,
        address owner,
        IRegistry subregistry,
        uint96 flags,
        uint64 expires
    ) external onlyController returns (uint256) {
        return registry.register(label, owner, subregistry, flags, expires);
    }

    function renew(uint256 tokenId, uint64 expires) external onlyController {
        registry.renew(tokenId, expires);
    }
}
