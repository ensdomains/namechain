// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistry} from "./IRegistry.sol";

interface IETHRegistry is IRegistry {
    error NameAlreadyRegistered(string label);
    error NameExpired(uint256 tokenId);
    error CannotReduceExpiration(uint64 oldExpiration, uint64 newExpiration);
    error CannotSetPastExpiration(uint64 expiry);

    event NameRenewed(uint256 indexed tokenId, uint64 newExpiration, address renewedBy);
    event NameRelinquished(uint256 indexed tokenId, address relinquishedBy);
    event TokenObserverSet(uint256 indexed tokenId, address observer);

    /**
     * @dev Registers a name.
     * @param label The label of the name to register.
     * @param owner The owner of the name.
     * @param registry The registry to register the name in.
     * @param resolver The resolver to use for the registration.
     * @param flags The flags to set for the name.
     * @param expires The expiration date of the name.
     */
    function register(string calldata label, address owner, IRegistry registry, address resolver, uint96 flags, uint64 expires)
        external
        returns (uint256 tokenId);

    /**
     * @dev Renews a name.
     * @param tokenId The ID of the name to renew.
     * @param expires The new expiration date.
     */
    function renew(uint256 tokenId, uint64 expires) external;

    /**
     * @dev Returns the expiry and flags of a name.
     * @param tokenId The ID of the name to get the data for.
     * @return expiry The expiry date of the name.
     * @return flags The flags of the name.
     */
    function nameData(uint256 tokenId) external view returns (uint64 expiry, uint32 flags);

}
