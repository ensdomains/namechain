// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistryCrier} from "./interfaces/IRegistryCrier.sol";

/**
 * @title RegistryCrier
 * @dev A singleton contract that emits NewRegistry events when registries are created.
 *      This contract has no state and no access control - it simply emits events.
 */
contract RegistryCrier is IRegistryCrier {
    /**
     * @dev Announce a new registry by emitting the NewRegistry event.
     *      Anyone can call this function as it only emits an event.
     * @param registry The address of the registry to announce
     */
    function newRegistry(address registry) external {
        emit NewRegistry(registry);
    }
}
