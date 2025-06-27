// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {DNSTXTScanner} from "./DNSTXTScanner.sol";
import {HexUtils} from "@ens/contracts/utils/HexUtils.sol";
import {BytesUtils} from "@ens/contracts/utils/BytesUtils.sol";
import {ENSIP19, COIN_TYPE_ETH} from "@ens/contracts/utils/ENSIP19.sol";

// resolver features
import {IFeatureSupporter, isFeatureSupported} from "../common/IFeatureSupporter.sol";
import {ResolverFeatures} from "../common/ResolverFeatures.sol";

// resolver profiles
import {IExtendedDNSResolver} from "@ens/contracts/resolvers/profiles/IExtendedDNSResolver.sol";
import {IMulticallable} from "@ens/contracts/resolvers/IMulticallable.sol";
import {IAddrResolver} from "@ens/contracts/resolvers/profiles/IAddrResolver.sol";
import {IAddressResolver} from "@ens/contracts/resolvers/profiles/IAddressResolver.sol";
import {IHasAddressResolver} from "@ens/contracts/resolvers/profiles/IHasAddressResolver.sol";
import {ITextResolver} from "@ens/contracts/resolvers/profiles/ITextResolver.sol";
import {IContentHashResolver} from "@ens/contracts/resolvers/profiles/IContentHashResolver.sol";
import {IPubkeyResolver} from "@ens/contracts/resolvers/profiles/IPubkeyResolver.sol";

import "hardhat/console.sol";

contract DNSTXTResolver is
    ERC165,
    IFeatureSupporter,
    IExtendedDNSResolver
{
    /// @notice The resolver profile cannot be answered.
    /// @dev Error selector: `0x5fe9a5df`
    error UnsupportedResolverProfile(bytes4 selector);

    /// @notice The supplied address could not be converted to `address`.
    /// @dev Error selector: `0x8d666f60`
    error InvalidEVMAddress(bytes addressBytes);

    /// @notice The data was not a hex string.
    /// @dev Matches: `/^0x[0-9a-fA-F]*$/`.
    ///      Error selector: `0x626777b1`
    error InvalidHexData(bytes data);

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
    function supportsFeature(bytes4 feature) public pure returns (bool) {
        return ResolverFeatures.RESOLVE_MULTICALL == feature;
    }

    function resolve(
        bytes calldata,
        bytes calldata data,
        bytes calldata context
    ) external view returns (bytes memory result) {
        if (bytes4(data) == IMulticallable.multicall.selector) {
            bytes[] memory m = abi.decode(data[4:], (bytes[]));
            for (uint256 i; i < m.length; i++) {
                (bool ok, bytes memory v) = address(this).staticcall(
                    abi.encodeCall(this.resolve, ("", m[i], context))
                );
                if (ok && v.length > 0) {
                    v = abi.decode(v, (bytes)); // unwrap resolve()
                }
                m[i] = v;
            }
            return abi.encode(m);
        } else if (bytes4(data) == IAddrResolver.addr.selector) {
            bytes memory v = _extractAddress(context, COIN_TYPE_ETH, true);
            return abi.encode(address(bytes20(v)));
        } else if (bytes4(data) == IAddressResolver.addr.selector) {
            (, uint256 coinType) = abi.decode(data[4:], (bytes32, uint256));
            return abi.encode(_extractAddress(context, coinType, true));
        } else if (bytes4(data) == IHasAddressResolver.hasAddr.selector) {
            (, uint256 coinType) = abi.decode(data[4:], (bytes32, uint256));
            return
                abi.encode(
                    _extractAddress(context, coinType, false).length > 0
                );
        } else if (bytes4(data) == ITextResolver.text.selector) {
            (, string memory key) = abi.decode(data[4:], (bytes32, string));
            bytes memory v = DNSTXTScanner.find(
                context,
                abi.encodePacked("t[", key, "]=")
            );
            return abi.encode(v);
        } else if (bytes4(data) == IContentHashResolver.contenthash.selector) {
            return abi.encode(_parseHex(DNSTXTScanner.find(context, "c=")));
        } else if (bytes4(data) == IPubkeyResolver.pubkey.selector) {
            bytes memory x = _parseHex(DNSTXTScanner.find(context, "x="));
            bytes memory y = _parseHex(DNSTXTScanner.find(context, "y="));
            return abi.encode(bytes32(x), bytes32(y));
        } else {
            revert UnsupportedResolverProfile(bytes4(data));
        }
    }

    function _extractAddress(
        bytes memory context,
        uint256 coinType,
        bool useDefault
    ) internal pure returns (bytes memory v) {
        if (!ENSIP19.isEVMCoinType(coinType)) {
            return
                _parseHex(
                    DNSTXTScanner.find(
                        context,
                        abi.encodePacked("a[", Strings.toString(coinType), "]=")
                    )
                );
        }
        if (coinType == COIN_TYPE_ETH) {
            v = DNSTXTScanner.find(context, "a[60]=");
        } else {
            v = DNSTXTScanner.find(
                context,
                abi.encodePacked(
                    "a[e",
                    Strings.toString(ENSIP19.chainFromCoinType(coinType)),
                    "]="
                )
            );
        }
        if (useDefault && v.length == 0) {
            v = DNSTXTScanner.find(context, "a[e0]=");
        }
        if (v.length > 0) {
            v = _parseHex(v);
            if (v.length != 20) {
                revert InvalidEVMAddress(v);
            }
        }
    }

    function _parseHex(
        bytes memory hexString
    ) internal pure returns (bytes memory v) {
        if (hexString.length > 0) {
            bool valid;
            if (
                hexString.length >= 2 &&
                hexString[0] == "0" &&
                hexString[1] == "x"
            ) {
                (v, valid) = HexUtils.hexToBytes(
                    hexString,
                    2,
                    hexString.length
                );
            }
            if (!valid) {
                revert InvalidHexData(hexString);
            }
        }
    }
}
