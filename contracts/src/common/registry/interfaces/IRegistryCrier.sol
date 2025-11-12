// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @dev Interface for the registry crier, which announces new registries by emitting events.
 *      This is a singleton contract used by all registries to emit NewRegistry events.
 */
interface IRegistryCrier {
    ////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////

    /**
     * @dev Emitted when a Registry is created and newRegistry function is called.
     * @param registry The address of the new registry
     */
    event NewRegistry(address indexed registry);

    ////////////////////////////////////////////////////////////////////////
    // Functions
    ////////////////////////////////////////////////////////////////////////

    /**
     * @dev Announce a new registry by emitting the NewRegistry event.
     *      This function has no access control - anyone can call it.
     * @param registry The address of the registry to announce
     */
    function newRegistry(address registry) external;
}
