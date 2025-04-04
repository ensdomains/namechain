// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistry} from "./IRegistry.sol";

interface IPermissionedRegistry is IRegistry {
    error NameAlreadyRegistered(string label);
    error NameExpired(uint256 tokenId);
    error CannotReduceExpiration(uint64 oldExpiration, uint64 newExpiration);
    error CannotSetPastExpiration(uint64 expiry);

    event NameRenewed(uint256 indexed tokenId, uint64 newExpiration, address renewedBy);
    event NameRelinquished(uint256 indexed tokenId, address relinquishedBy);
    event TokenObserverSet(uint256 indexed tokenId, address observer);

    function register(string calldata label, address owner, IRegistry registry, address resolver, uint256 roleBitmap, uint64 expires) external returns (uint256 tokenId);
    function renew(uint256 tokenId, uint64 expires) external;
    function relinquish(uint256 tokenId) external;
    function setTokenObserver(uint256 tokenId, address _observer) external;
    function setSubregistry(uint256 tokenId, IRegistry registry) external;
    function setResolver(uint256 tokenId, address resolver) external;
    function getNameData(string calldata label) external view returns (uint256 tokenId, uint64 expiry, uint32 tokenIdVersion);
    function getExpiry(uint256 tokenId) external view returns (uint64 expiry);
    function tokenIdResource(uint256 tokenId) external view returns(bytes32);
    function resourceTokenId(bytes32 resource) external view returns (uint256);
}