// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {CCIPReader} from "@ens/contracts/ccipRead/CCIPReader.sol";
import {HexUtils} from "@ens/contracts/utils/HexUtils.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {IRemoteRegistryResolver} from "../eth/IRemoteRegistryResolver.sol";
import {IFeatureSupporter} from "@ens/contracts/utils/IFeatureSupporter.sol";
import {ResolverFeatures} from "@ens/contracts/resolvers/ResolverFeatures.sol";
import {IExtendedDNSResolver} from "@ens/contracts/resolvers/profiles/IExtendedDNSResolver.sol";

contract DNSRemoteRegistryResolver is
    ERC165,
    CCIPReader,
    IFeatureSupporter,
    IExtendedDNSResolver
{
    IRemoteRegistryResolver public immutable remoteRegistryResolver;

    constructor(IRemoteRegistryResolver _remoteRegistryResolver) CCIPReader(0) {
        remoteRegistryResolver = _remoteRegistryResolver;
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165) returns (bool) {
        return
            type(IExtendedDNSResolver).interfaceId == interfaceId ||
            type(IFeatureSupporter).interfaceId == interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IFeatureSupporter
    function supportsFeature(bytes4 feature) external pure returns (bool) {
        return ResolverFeatures.RESOLVE_MULTICALL == feature;
    }

    function resolve(
        bytes calldata name,
        bytes calldata data,
        bytes calldata context
    ) external view returns (bytes memory) {
        (address registry, bytes32 nodeSuffix) = _parseContext(context);
        ccipRead(
            address(remoteRegistryResolver),
            abi.encodeCall(
                IRemoteRegistryResolver.resolveWithRegistry,
                (registry, nodeSuffix, name, data)
            )
        );
    }

    function _parseContext(
        bytes calldata context
    ) internal pure returns (address registry, bytes32 nodeSuffix) {
        require(context.length > 43, "expected <address> <suffix>");
        (bool valid, bytes32 word) = _parseSmall0xString(context, 0, 20);
        require(valid, "invalid address");
        registry = address(uint160(uint256(word)));
        require(context[42] == " ", "expected space");
        nodeSuffix = NameCoder.namehash(
            NameCoder.encode(string(context[43:])),
            0
        );
    }

    function _parseSmall0xString(
        bytes memory v,
        uint256 offset,
        uint256 byteCount
    ) internal pure returns (bool valid, bytes32 word) {
        (word, valid) = HexUtils.hexStringToBytes32(
            v,
            offset + 2,
            offset + 2 + (byteCount << 1)
        );
        valid = valid && v[offset] == "0" && v[offset + 1] == "x";
    }
}
