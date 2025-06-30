// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {CCIPBatcher, OffchainLookup} from "@ens/contracts/ccipRead/CCIPBatcher.sol";
import {DNSSEC} from "@ens/contracts/dnssec-oracle/DNSSEC.sol";
import {RRUtils} from "@ens/contracts/dnssec-oracle/RRUtils.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {BytesUtils} from "@ens/contracts/utils/BytesUtils.sol";
import {HexUtils} from "@ens/contracts/utils/HexUtils.sol";
import {IFeatureSupporter, isFeatureSupported} from "../../common/IFeatureSupporter.sol";
import {ResolverFeatures} from "../../common/ResolverFeatures.sol";

// resolver profiles
import {IExtendedResolver} from "@ens/contracts/resolvers/profiles/IExtendedResolver.sol";
import {IExtendedDNSResolver} from "@ens/contracts/resolvers/profiles/IExtendedDNSResolver.sol";
import {IMulticallable} from "@ens/contracts/resolvers/IMulticallable.sol";

/// @dev Gateway interface for DNSSEC oracle.
interface IDNSGateway {
    function resolve(
        bytes memory name,
        uint16 qtype
    ) external returns (DNSSEC.RRSetWithSignature[] memory);
}

/// @dev Partial interface for `UniversalResolver`.
interface IUniversalResolverStub {
    function findResolver(
        bytes memory
    ) external view returns (address, bytes32, uint256);
    function batchGateways() external view returns (string[] memory);
}

uint16 constant CLASS_INET = 1;
uint16 constant TYPE_TXT = 16;

/// @dev DNS TXT record prefix for context data.
bytes constant TXT_PREFIX = "ENS1 ";

/// @title DNSTLDResolver
/// @notice Resolver that performs imported DNS fallback to V1 and gasless DNS resolution.
contract DNSTLDResolver is
    IFeatureSupporter,
    IExtendedResolver,
    CCIPBatcher,
    Ownable,
    ERC165
{
    IUniversalResolverStub public immutable universalResolverV1;
    IUniversalResolverStub public immutable universalResolverV2;
    DNSSEC public immutable oracleVerifier;
    string[] _gateways;

    /// @dev `name` does not exist.
    ///      Error selector: `0x5fe9a5df`
    /// @param name The DNS-encoded ENS name.
    error UnreachableName(bytes name);

    /// @dev Some raw TXT data was incorrectly encoded.
    ///      Error selector: `0xf4ba19b7`
    error InvalidTXT();

    constructor(
        IUniversalResolverStub _universalResolverV1,
        IUniversalResolverStub _universalResolverV2,
        DNSSEC _oracleVerifier,
        string[] memory gateways
    ) Ownable(msg.sender) {
        universalResolverV1 = _universalResolverV1;
        universalResolverV2 = _universalResolverV2;
        oracleVerifier = _oracleVerifier;
        _gateways = gateways;
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

    /// @notice Set the DNSSEC oracle gateways.
    /// @param gateways The gateway URLs.
    function setOracleGateways(string[] memory gateways) external onlyOwner {
        _gateways = gateways;
    }

    /// @notice Get the DNSSEC oracle gateways.
    /// @return The gateway URLs.
    function oracleGateways() external view returns (string[] memory) {
        return _gateways;
    }

    /// @notice Resolve `name` using V1 or DNSSEC.
    /// @notice Caller should enable EIP-3668.
    /// @dev This function executes over multiple steps.
    ///
    /// 1. If there exists a resolver in V1, go to 4.
    /// 2. Query the DNSSEC oracle for TXT records.
    /// 3. Verify TXT records, find ENS1 record, parse resolver and context.
    /// 4. Call the resolver and return the requested records.
    function resolve(
        bytes calldata name,
        bytes calldata data
    ) external view returns (bytes memory) {
        (address resolver, , uint256 offset) = universalResolverV1.findResolver(
            name
        );
        if (
            resolver != address(0) &&
            (offset == 0 ||
                ERC165Checker.supportsERC165InterfaceUnchecked(
                    resolver,
                    type(IExtendedResolver).interfaceId
                ))
        ) {
            _callResolver(resolver, name, data, false, "");
        }
        revert OffchainLookup(
            address(this),
            _gateways,
            abi.encodeCall(IDNSGateway.resolve, (name, TYPE_TXT)),
            this.resolveOracleCallback.selector, // ==> step 2
            abi.encode(name, data)
        );
    }

    /// @dev CCIP-Read callback for `resolve()` from calling the DNSSEC oracle.
    ///      Reverts `UnreachableName` if no "ENS1" TXT record is found.
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
                    _callResolver(resolver, name, call, true, context); // ==> step 3
                }
            }
        }
        revert UnreachableName(name);
    }

    /// @dev Efficiently call another resolver.
    ///      Reverts `UnreachableName` if resolver is not a contract.
    /// @param resolver The resolver to call.
    /// @param name The name to resolve.
    /// @param call The calldata.
    /// @param checkDNS True if `IExtendedDNSResolver` should be considered.
    /// @param context The context for `IExtendedDNSResolver`.
    function _callResolver(
        address resolver,
        bytes memory name,
        bytes memory call,
        bool checkDNS,
        bytes memory context
    ) internal view {
        if (resolver.code.length == 0) {
            revert UnreachableName(name);
        }
        bool multi = bytes4(call) == IMulticallable.multicall.selector;
        bool direct = ERC165Checker.supportsERC165InterfaceUnchecked(
            resolver,
            type(IFeatureSupporter).interfaceId
        ) &&
            (!multi ||
                IFeatureSupporter(resolver).supportsFeature(
                    ResolverFeatures.RESOLVE_MULTICALL
                ));
        bytes[] memory calls;
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
            checkDNS &&
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
                for (uint256 i; i < calls.length; ++i) {
                    calls[i] = abi.encodeCall(
                        IExtendedDNSResolver.resolve,
                        (name, calls[i], context)
                    );
                }
            }
        } else if (
            ERC165Checker.supportsERC165InterfaceUnchecked(
                resolver,
                type(IExtendedResolver).interfaceId
            )
        ) {
            if (direct) {
                ccipRead(
                    resolver,
                    abi.encodeCall(IExtendedResolver.resolve, (name, call))
                );
            } else {
                extended = true;
                for (uint256 i; i < calls.length; ++i) {
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

    /// @dev CCIP-Read callback for `_callResolver()` from batch calling the gasless DNS resolver.
    /// @param response The response data from the batch gateway.
    /// @param extraData The abi-encoded properties of the call.
    /// @return result The response from the resolver.
    function resolveBatchCallback(
        bytes calldata response,
        bytes calldata extraData
    ) external pure returns (bytes memory) {
        Batch memory batch = abi.decode(response, (Batch));
        (bool multi, bool extended) = abi.decode(extraData, (bool, bool));
        uint256 n = batch.lookups.length;
        if (extended) {
            for (uint256 i; i < n; ++i) {
                Lookup memory lu = batch.lookups[i];
                if ((lu.flags & FLAGS_ANY_ERROR) == 0) {
                    lu.data = abi.decode(lu.data, (bytes)); // unwrap resolve()
                }
            }
        }
        if (multi) {
            bytes[] memory m = new bytes[](n);
            for (uint256 i; i < n; ++i) {
                m[i] = batch.lookups[i].data;
            }
            return abi.encode(m);
        } else {
            return batch.lookups[0].data;
        }
    }

    /// @dev Parse the TXT record into resolver and context.
    ///      Format: "ENS1 <name or address> <context?>".
    /// @param txt The TXT data.
    /// @return resolver The resolver address or null if wrong format or name didn't resolve.
    /// @return context The optional context data.
    function _parseTXT(
        bytes memory txt
    ) internal view returns (address resolver, bytes memory context) {
        uint256 n = TXT_PREFIX.length;
        if (txt.length >= n && BytesUtils.equals(txt, 0, TXT_PREFIX, 0, n)) {
            uint256 sep = BytesUtils.find(txt, n, txt.length - n, " ");
            if (sep < txt.length) {
                context = BytesUtils.substring(
                    txt,
                    sep + 1,
                    txt.length - sep - 1
                );
            } else {
                sep = txt.length;
            }
            resolver = _parseResolver(BytesUtils.substring(txt, n, sep - n));
        }
    }

    /// @dev Parse the value into a resolver address.
    ///      If the value matches `/^0x[0-9a-f]{40}$/`, it's a literal address.
    ///      Otherwise, it's considered a name and resolved in the registry.
    ///      Reverts `DNSEncodingFailed` if the name cannot be encoded.
    /// @param v The address or name.
    /// @return resolver The corresponding resolver address.
    function _parseResolver(
        bytes memory v
    ) internal view returns (address resolver) {
        if (v.length > 2 && v[0] == "0" && v[1] == "x") {
            (address addr, bool valid) = HexUtils.hexToAddress(v, 2, v.length);
            if (valid) {
                return addr;
            }
        }
        (resolver, , ) = universalResolverV2.findResolver(
            NameCoder.encode(string(v))
        );
    }

    /// @dev Decode `v[pos:end]` as raw TXT chunks.
    ///      Encoding: `[byte(n) + <n bytes>]...`
    ///      Reverts `InvalidTXT` if the data is malformed.
    /// @param v The raw TXT data.
    /// @param pos The offset of the record data.
    /// @param end The upper bound of the record data.
    /// @return txt The decoded TXT value.
    function _readTXT(
        bytes memory v,
        uint256 pos,
        uint256 end
    ) internal pure returns (bytes memory txt) {
        if (end > v.length) revert InvalidTXT();
        txt = new bytes(end - pos);
        assembly {
            let ptr := add(v, 32)
            pos := add(ptr, pos)
            end := add(ptr, end)
            ptr := add(txt, 32)
            // prettier-ignore
            for { } lt(pos, end) { } {
                let size := shr(248, mload(pos))
                pos := add(pos, 1)
                if size {
                    let next := add(pos, size)
                    if gt(next, end) {
                        end := 0 // overflow
                        break
                    }
                    mcopy(ptr, pos, size)
                    pos := next
                    ptr := add(ptr, size)
                }
            }
            mstore(txt, sub(ptr, add(txt, 32))) // truncate
        }
        if (pos != end) revert InvalidTXT();
    }

    /// TODO: move this to CCIPBatcher
    /// @dev Create a `Batch` for a single target with multiple calls.
    function _createBatch(
        address target,
        bytes[] memory calls
    ) internal view returns (Batch memory) {
        Lookup[] memory lookups = new Lookup[](calls.length);
        for (uint256 i; i < calls.length; ++i) {
            Lookup memory lu = lookups[i];
            lu.target = target;
            lu.call = calls[i];
        }
        return Batch(lookups, universalResolverV2.batchGateways());
    }
}
