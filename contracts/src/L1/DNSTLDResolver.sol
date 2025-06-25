// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {UniversalResolver} from "../universalResolver/UniversalResolver.sol";
import {CCIPBatcher, OffchainLookup} from "@ens/contracts/ccipRead/CCIPBatcher.sol";
import {DNSSEC} from "@ens/contracts/dnssec-oracle/DNSSEC.sol";
import {RRUtils} from "@ens/contracts/dnssec-oracle/RRUtils.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {BytesUtils} from "@ens/contracts/utils/BytesUtils.sol";
import {HexUtils} from "@ens/contracts/utils/HexUtils.sol";

// resolver profiles
import {IExtendedResolver} from "@ens/contracts/resolvers/profiles/IExtendedResolver.sol";
import {IExtendedDNSResolver} from "@ens/contracts/resolvers/profiles/IExtendedDNSResolver.sol";
import {IMulticallable} from "@ens/contracts/resolvers/IMulticallable.sol";

// resolver features
import {IFeatureSupporter, isFeatureSupported} from "../common/IFeatureSupporter.sol";
import {ResolverFeatures} from "../common/ResolverFeatures.sol";

interface IDNSGateway {
    function resolve(
        bytes memory name,
        uint16 qtype
    ) external returns (DNSSEC.RRSetWithSignature[] memory);
}

interface IUniversalResolverStub {
    function findResolver(
        bytes memory
    ) external view returns (address, bytes32, uint256);
    function batchGateways() external view returns (string[] memory);
}

uint16 constant CLASS_INET = 1;
uint16 constant TYPE_TXT = 16;

bytes constant PREFIX = "ENS1 ";
uint256 constant PREFIX_LENGTH = 5; // PREFIX.length

contract DNSTLDResolver is
    ERC165,
    IFeatureSupporter,
    IExtendedResolver,
    CCIPBatcher
{
    /// @dev `name` does not exist.
    ///      Error selector: `0x5fe9a5df`
    /// @param name The DNS-encoded ENS name.
    error UnreachableName(bytes name);

    /// @dev Some raw TXT data was incorrectly encoded.
    ///      Error selector: `0xf4ba19b7`
    error InvalidTXT();

    IUniversalResolverStub public immutable universalResolverV1;
    IUniversalResolverStub public immutable universalResolverV2;
    DNSSEC public immutable oracleVerifier;
    string[] public oracleGateways;

    constructor(
        IUniversalResolverStub _universalResolverV1,
        IUniversalResolverStub _universalResolverV2,
        DNSSEC _oracleVerifier,
        string[] memory _oracleGateways
    ) {
        universalResolverV1 = _universalResolverV1;
        universalResolverV2 = _universalResolverV2;
        oracleVerifier = _oracleVerifier;
        oracleGateways = _oracleGateways;
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165) returns (bool) {
        return
            type(IExtendedResolver).interfaceId == interfaceId ||
            type(IFeatureSupporter).interfaceId == interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IFeatureSupporter
    function supportsFeature(bytes4 feature) public pure returns (bool) {
        return ResolverFeatures.RESOLVE_MULTICALL == feature;
    }

    /// DNS Resolution with Fallback:
    /// 0. If there exists a resolver in V1, go to step 3.
    /// 1. Query the DNSSEC oracle for TXT records.
    /// 2. Verify TXT records, find ENS1 record,  parse ENS1 record into resolver and context.
    /// 3. Call the resolver and return the records.
    /// @notice Callers should enable EIP-3668.
    /// @dev This function executes over multiple steps (step 1 of 3).
    function resolve(
        bytes calldata name,
        bytes calldata data
    ) external view returns (bytes memory) {
        (address resolver, , uint256 offset) = universalResolverV1.findResolver(
            name
        );
        if (resolver == address(0)) {
            revert OffchainLookup(
                address(this),
                oracleGateways,
                abi.encodeCall(IDNSGateway.resolve, (name, TYPE_TXT)),
                this.resolveOracleCallback.selector,
                abi.encode(name, data)
            );
        }
        if (!_isExtended(resolver) && offset != 0) {
            revert UnreachableName(name);
        }
        _callResolver(resolver, name, data, false, "");
    }

    /// @dev CCIP-Read callback for `resolve()` from calling the DNSSEC oracle (step 2 of 3).
    ///      Reverts `UnreachableName` if no "ENS1" TXT record is found.
    ///      Reverts `UnreachableName` if resolver is not a contract.
    /// @param response The response data.
    /// @param extraData The contextual data passed from `resolve()`.
    /// @return The abi-encoded result from the resolver.
    function resolveOracleCallback(
        bytes calldata response,
        bytes calldata extraData
    ) external view returns (bytes memory) {
        (bytes memory name, bytes memory call) = abi.decode(
            extraData,
            (bytes, bytes)
        );
        DNSSEC.RRSetWithSignature[] memory rrsets = abi.decode(
            response,
            (DNSSEC.RRSetWithSignature[])
        );
        (bytes memory data, ) = oracleVerifier.verifyRRSet(rrsets);
        for (
            RRUtils.RRIterator memory iter = RRUtils.iterateRRs(data, 0);
            !RRUtils.done(iter);
            RRUtils.next(iter)
        ) {
            if (
                iter.class == CLASS_INET &&
                iter.dnstype == TYPE_TXT &&
                BytesUtils.equals(iter.data, iter.offset, name, 0, name.length)
            ) {
                (address resolver, bytes memory context) = _parseTXT(
                    _readTXT(iter.data, iter.rdataOffset, iter.nextOffset)
                );
                if (resolver != address(0)) {
                    _callResolver(resolver, name, call, true, context);
                }
            }
        }
        revert UnreachableName(name);
    }

    function _callResolver(
        address resolver,
        bytes memory name,
        bytes memory call,
        bool tryContext,
        bytes memory context
    ) internal view {
        if (resolver.code.length == 0) {
            revert UnreachableName(name);
        }
        bool direct = isFeatureSupported(
            resolver,
            ResolverFeatures.RESOLVE_MULTICALL
        );
        bytes[] memory calls;
        bool multi = bytes4(call) == IMulticallable.multicall.selector;
        if (multi) {
            calls = abi.decode(
                BytesUtils.substring(call, 4, call.length - 4),
                (bytes[])
            );
        } else {
            calls = new bytes[](1);
            calls[0] = call;
        }
        bool extended;
        if (
            tryContext &&
            ERC165Checker.supportsERC165InterfaceUnchecked(
                resolver,
                type(IExtendedDNSResolver).interfaceId
            )
        ) {
            if (direct) {
                ccipRead(
                    resolver,
                    abi.encodeCall(
                        IExtendedDNSResolver.resolve,
                        (name, call, context)
                    )
                );
            } else {
                extended = true;
                for (uint256 i; i < calls.length; i++) {
                    calls[i] = abi.encodeCall(
                        IExtendedDNSResolver.resolve,
                        (name, calls[i], context)
                    );
                }
            }
        } else if (_isExtended(resolver)) {
            if (direct) {
                ccipRead(
                    resolver,
                    abi.encodeCall(IExtendedResolver.resolve, (name, call))
                );
            } else {
                extended = true;
                for (uint256 i; i < calls.length; i++) {
                    calls[i] = abi.encodeCall(
                        IExtendedResolver.resolve,
                        (name, calls[i])
                    );
                }
            }
        }
        ccipRead(
            address(this),
            abi.encodeCall(this.ccipBatch, (_createBatch(resolver, calls))),
            this.resolveBatchCallback.selector,
            abi.encode(multi, extended)
        );
    }

    /// @dev CCIP-Read callback for `_callResolver()` from calling the DNS resolver (step 3 of 3).
    /// @param response The response data.
    /// @param extraData The 
    /// @return result The abi-encoded result.
    function resolveBatchCallback(
        bytes calldata response,
        bytes calldata extraData
    ) external pure returns (bytes memory) {
        Batch memory batch = abi.decode(response, (Batch));
        (bool multi, bool extended) = abi.decode(extraData, (bool, bool));
        if (extended) {
            for (uint256 i; i < batch.lookups.length; i++) {
                Lookup memory lu = batch.lookups[i];
                if ((lu.flags & FLAGS_ANY_ERROR) == 0) {
                    lu.data = abi.decode(lu.data, (bytes));
                }
            }
        }
        if (multi) {
            uint256 n = batch.lookups.length;
            bytes[] memory m = new bytes[](n);
            for (uint256 i; i < m.length; i++) {
                m[i] = batch.lookups[i].data;
            }
            return abi.encode(m);
        } else {
            return batch.lookups[0].data;
        }
    }

    /// @dev Parse the TXT record into resolver and context.
    ///      Format: "ENS1 <name or address> <context?>"
    /// @param txt The TXT data.
    /// @return resolver The resolver address or null if wrong format.
    /// @return context The optional context data.
    function _parseTXT(
        bytes memory txt
    ) internal view returns (address resolver, bytes memory context) {
        if (
            txt.length >= PREFIX_LENGTH &&
            BytesUtils.equals(txt, 0, PREFIX, 0, PREFIX_LENGTH)
        ) {
            uint256 sep = BytesUtils.find(
                txt,
                PREFIX_LENGTH,
                txt.length - PREFIX_LENGTH,
                " "
            );
            if (sep < txt.length) {
                context = _trim(
                    BytesUtils.substring(txt, sep + 1, txt.length - sep - 1)
                );
            } else {
                sep = txt.length;
            }
            resolver = _parseResolver(
                _trim(
                    BytesUtils.substring(
                        txt,
                        PREFIX_LENGTH,
                        sep - PREFIX_LENGTH
                    )
                )
            );
        }
    }

    /// @dev Parse the value into an address.
    ///      If the value matches `/^0x[0-9a-f][40]$/`.
    function _parseResolver(
        bytes memory v
    ) internal view returns (address resolver) {
        if (v[0] == "0" && v[1] == "x") {
            (address addr, bool valid) = HexUtils.hexToAddress(v, 2, v.length);
            if (valid) {
                return addr;
            }
        }
        (resolver, , ) = universalResolverV2.findResolver(
            NameCoder.encode(string(v))
        );
    }

    /// @dev Decode `data[pos:end]` as raw TXT chunks.
    ///      Encoding: `[byte(n) + <n bytes>]...`
    /// @param data The raw TXT data.
    /// @param pos The offset of the record data.
    /// @param end The upper bound of the record data.
    function _readTXT(
        bytes memory data,
        uint256 pos,
        uint256 end
    ) internal pure returns (bytes memory txt) {
        while (pos < end) {
            uint256 size = BytesUtils.readUint8(data, pos++);
            if (size > 0) {
                txt = abi.encodePacked(
                    txt,
                    BytesUtils.substring(data, pos, size)
                );
                pos += size;
            }
        }
        if (pos != end) revert InvalidTXT();
    }

    /// @dev Determine if the resolver is `IExtendedResolver`.
    function _isExtended(address resolver) internal view returns (bool) {
        return
            ERC165Checker.supportsERC165InterfaceUnchecked(
                resolver,
                type(IExtendedResolver).interfaceId
            );
    }

    function _createBatch(
        address target,
        bytes[] memory calls
    ) internal view returns (Batch memory) {
        Lookup[] memory lookups = new Lookup[](calls.length);
        for (uint256 i; i < calls.length; i++) {
            Lookup memory lu = lookups[i];
            lu.target = target;
            lu.call = calls[i];
        }
        return Batch(lookups, universalResolverV2.batchGateways());
    }

    /// @dev Trim surrounding spaces.
    ///      eg. _trim(" abc  ") = "abc".
    ///      Warning: mutates the memory in place.
    /// @return The truncated string.
    function _trim(bytes memory v) internal pure returns (bytes memory) {
        uint256 n = v.length;
        while (n > 0 && v[n - 1] == " ") --n;
        uint256 i;
        while (i < n && v[i] == " ") ++i;
        assembly {
            v := add(v, i) // skip
            mstore(v, sub(n, i)) // truncate
        }
        return v;
    }
}
