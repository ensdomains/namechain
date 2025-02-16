// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IETHRegistrar} from "./IETHRegistrar.sol";
import {IRegistry} from "./IRegistry.sol";
import {IERC1155Singleton} from "./IERC1155Singleton.sol";
import {IETHRegistry} from "./IETHRegistry.sol";

// TODO: integrate pricing oracle logic
contract ETHRegistryController is IETHRegistrar {
    IETHRegistry public registry;

    constructor(address _registry) {
        registry = IETHRegistry(_registry);
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
    ) external returns (uint256) {
        return registry.register(label, owner, subregistry, flags, expires);
    }

    function renew(uint256 tokenId, uint64 expires) external {
        registry.renew(tokenId, expires);
    }
}
