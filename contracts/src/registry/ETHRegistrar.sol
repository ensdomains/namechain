// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IETHRegistrar} from "./IETHRegistrar.sol";
import {IRegistry} from "./IRegistry.sol";
import {IERC1155Singleton} from "./IERC1155Singleton.sol";
import {IETHRegistry} from "./IETHRegistry.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract ETHRegistrar is IETHRegistrar, AccessControl {
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    IETHRegistry public registry;

    constructor(address _registry) {
        registry = IETHRegistry(_registry);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
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
    ) external onlyRole(CONTROLLER_ROLE) returns (uint256) {
        return registry.register(label, owner, subregistry, flags, expires);
    }

    function renew(uint256 tokenId, uint64 expires) external onlyRole(CONTROLLER_ROLE) {
        registry.renew(tokenId, expires);
    }
}
