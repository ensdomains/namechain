// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {BytesUtils} from "@ens/contracts/utils/BytesUtils.sol";

import {IOffchainResolverMetadataProvider} from "./interfaces/IOffchainResolverMetadataProvider.sol";

/// @notice Base contract for providing offchain resolver metadata.
abstract contract OffchainResolverMetadataProvider is IOffchainResolverMetadataProvider, Ownable, ERC165 {
    /// @notice DNS-encoded name for this metadata provider.
    bytes public dnsEncodedName;

    /// @notice RPC URLs for querying offchain data.
    string[] public rpcURLs;

    /// @notice Chain ID where offchain data is stored.
    uint256 public chainId;

    /// @notice Base registry address on the target chain.
    address public baseRegistry;

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165) returns (bool) {
        return
            type(IOffchainResolverMetadataProvider).interfaceId == interfaceId || super.supportsInterface(interfaceId);
    }

    /// @notice Set the metadata for offchain resolution discovery.
    /// @param dnsEncodedName_ The DNS-encoded name (e.g., hex"03657468" for "eth").
    /// @param rpcURLs_ The JSON RPC endpoints for querying offchain data.
    /// @param chainId_ The chain ID where offchain data is stored.
    /// @param baseRegistry_ The base registry address on the target chain.
    function setMetadata(
        bytes memory dnsEncodedName_,
        string[] memory rpcURLs_,
        uint256 chainId_,
        address baseRegistry_
    ) external onlyOwner {
        dnsEncodedName = dnsEncodedName_;
        rpcURLs = rpcURLs_;
        chainId = chainId_;
        baseRegistry = baseRegistry_;
        emit MetadataChanged(dnsEncodedName_, rpcURLs_, chainId_, baseRegistry_);
    }

    /// @inheritdoc IOffchainResolverMetadataProvider
    function metadata(
        bytes calldata name
    ) external view returns (string[] memory rpcURLs_, uint256 chainId_, address baseRegistry_) {
        if (!_hasSuffix(name, dnsEncodedName)) {
            return (new string[](0), 0, address(0));
        }
        return (rpcURLs, chainId, baseRegistry);
    }

    /// @dev Check if name ends with the configured suffix.
    function _hasSuffix(bytes calldata name, bytes memory suffix) internal pure returns (bool) {
        if (suffix.length == 0 || name.length < suffix.length) {
            return false;
        }
        uint256 offset = name.length - suffix.length;
        return BytesUtils.equals(bytes(name[offset:]), 0, suffix);
    }
}
