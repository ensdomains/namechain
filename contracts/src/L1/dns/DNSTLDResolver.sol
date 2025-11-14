// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {CCIPBatcher, CCIPReader, OffchainLookup} from "@ens/contracts/ccipRead/CCIPBatcher.sol";
import {IGatewayProvider} from "@ens/contracts/ccipRead/IGatewayProvider.sol";
import {DNSSEC} from "@ens/contracts/dnssec-oracle/DNSSEC.sol";
import {IDNSGateway} from "@ens/contracts/dnssec-oracle/IDNSGateway.sol";
import {RRUtils} from "@ens/contracts/dnssec-oracle/RRUtils.sol";
import {IMulticallable} from "@ens/contracts/resolvers/IMulticallable.sol";
import {IAddrResolver} from "@ens/contracts/resolvers/profiles/IAddrResolver.sol";
import {ICompositeResolver} from "@ens/contracts/resolvers/profiles/ICompositeResolver.sol";
import {IExtendedDNSResolver} from "@ens/contracts/resolvers/profiles/IExtendedDNSResolver.sol";
import {IExtendedResolver} from "@ens/contracts/resolvers/profiles/IExtendedResolver.sol";
import {IVerifiableResolver} from "@ens/contracts/resolvers/profiles/IVerifiableResolver.sol";
import {ResolverFeatures} from "@ens/contracts/resolvers/ResolverFeatures.sol";
import {
    RegistryUtils as RegistryUtilsV1,
    ENS
} from "@ens/contracts/universalResolver/RegistryUtils.sol";
import {BytesUtils} from "@ens/contracts/utils/BytesUtils.sol";
import {HexUtils} from "@ens/contracts/utils/HexUtils.sol";
import {IERC7996} from "@ens/contracts/utils/IERC7996.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {ArrayLengthMismatch} from "../../common/CommonErrors.sol";
import {
    ResolverProfileDecoderLib
} from "../../common/resolver/libraries/ResolverProfileDecoderLib.sol";
import {LibRegistry, IRegistry} from "../../universalResolver/libraries/LibRegistry.sol";

/// @dev DNS class for the "Internet" according to RFC-1035.
uint16 constant CLASS_INET = 1;

/// @dev DNS query/resource type for TXT according to RFC-1035.
uint16 constant QTYPE_TXT = 16;

/// @dev DNS TXT record prefix for ENS data.
bytes constant TXT_PREFIX = "ENS1 ";

/// @dev The hash of text() key to access "context" from `ENS1 <resolver> <context>`.
string constant TEXT_KEY_DNSSEC_CONTEXT = "eth.ens.dnssec-context";

/// @notice Resolver that performs imported DNS fallback to V1 and gasless DNS resolution.
///
/// 0. Note: an imported DNS name will not reach this resolver unless set specifically.
/// 1. If there exists a resolver in V1, go to 4.
/// 2. Query the DNSSEC oracle for TXT records.
/// 3. Verify TXT records, find ENS1 record, parse resolver and context.
/// 4. Call the resolver and return the requested records.
///
contract DNSTLDResolver is IERC7996, ICompositeResolver, IVerifiableResolver, CCIPBatcher, ERC165 {
    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////
    ENS public immutable ENS_REGISTRY_V1;

    address public immutable DNS_TLD_RESOLVER_V1;

    IRegistry public immutable ROOT_REGISTRY;

    DNSSEC public immutable DNSSEC_ORACLE;

    /// @dev Shared DNSSEC oracle gateway provider.
    IGatewayProvider public immutable ORACLE_GATEWAY_PROVIDER;

    /// @dev Shared batch gateway provider.
    IGatewayProvider public immutable BATCH_GATEWAY_PROVIDER;

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    /// @notice `name` does not exist.
    /// @dev Error selector: `0x5fe9a5df`
    /// @param name The DNS-encoded ENS name.
    error UnreachableName(bytes name);

    /// @notice Some raw TXT data was incorrectly encoded.
    /// @dev Error selector: `0xf4ba19b7`
    error InvalidTXT();

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(
        ENS ensRegistryV1,
        address dnsTLDResolverV1,
        IRegistry rootRegistry,
        DNSSEC dnssecOracle,
        IGatewayProvider oracleGatewayProvider,
        IGatewayProvider batchGatewayProvider
    ) CCIPReader(DEFAULT_UNSAFE_CALL_GAS) {
        ENS_REGISTRY_V1 = ensRegistryV1;
        DNS_TLD_RESOLVER_V1 = dnsTLDResolverV1;
        ROOT_REGISTRY = rootRegistry;
        DNSSEC_ORACLE = dnssecOracle;
        ORACLE_GATEWAY_PROVIDER = oracleGatewayProvider;
        BATCH_GATEWAY_PROVIDER = batchGatewayProvider;
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165) returns (bool) {
        return
            type(IExtendedResolver).interfaceId == interfaceId ||
            type(ICompositeResolver).interfaceId == interfaceId ||
            type(IVerifiableResolver).interfaceId == interfaceId ||
            type(IERC7996).interfaceId == interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IERC7996
    function supportsFeature(bytes4 feature) public pure returns (bool) {
        return ResolverFeatures.RESOLVE_MULTICALL == feature;
    }

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    /// @inheritdoc IVerifiableResolver
    function verifierMetadata(
        bytes calldata name
    ) external view returns (address verifier, string[] memory gateways) {
        if (_determineMainnetResolver(name) == address(0)) {
            verifier = address(DNSSEC_ORACLE);
            gateways = ORACLE_GATEWAY_PROVIDER.gateways();
        }
    }

    /// @inheritdoc ICompositeResolver
    function requiresOffchain(bytes calldata name) external view returns (bool offchain) {
        offchain = _determineMainnetResolver(name) == address(0);
    }

    /// @inheritdoc ICompositeResolver
    /// @dev This function executes over multiple steps.
    function getResolver(bytes calldata name) external view returns (address, bool) {
        address resolver = _determineMainnetResolver(name);
        if (resolver != address(0)) {
            return (resolver, false);
        }
        revert OffchainLookup(
            address(this),
            ORACLE_GATEWAY_PROVIDER.gateways(),
            abi.encodeCall(IDNSGateway.resolve, (name, QTYPE_TXT)),
            this.getResolverCallback.selector, // ==> step 2
            name
        );
    }

    /// @notice CCIP-Read callback for `getResolver()`.
    function getResolverCallback(
        bytes calldata response,
        bytes calldata name
    ) external view returns (address, bool) {
        (address resolver, ) = _verifyDNSSEC(name, response);
        return (resolver, true);
    }

    /// @notice Resolve `name` using V1 or DNSSEC.
    ///         Caller should enable EIP-3668.
    ///
    /// @dev This function executes over multiple steps.
    function resolve(
        bytes calldata name,
        bytes calldata data
    ) external view returns (bytes memory) {
        address resolver = _determineMainnetResolver(name);
        if (resolver != address(0)) {
            return _callResolver(resolver, name, data, false, ""); // ==> step 2
        }
        revert OffchainLookup(
            address(this),
            ORACLE_GATEWAY_PROVIDER.gateways(),
            abi.encodeCall(IDNSGateway.resolve, (name, QTYPE_TXT)),
            this.resolveOracleCallback.selector, // ==> step 2
            abi.encode(name, data)
        );
    }

    /// @notice CCIP-Read callback for `resolve()` from calling the DNSSEC oracle.
    ///         Reverts `UnreachableName` if no "ENS1" TXT record is found.
    ///
    /// @param response The response data.
    /// @param extraData The contextual data passed from `resolve()`.
    ///
    /// @return The abi-encoded result from the resolver.
    function resolveOracleCallback(
        bytes calldata response,
        bytes calldata extraData
    ) external view returns (bytes memory) {
        (bytes memory name, bytes memory call) = abi.decode(extraData, (bytes, bytes));
        (address resolver, bytes memory context) = _verifyDNSSEC(name, response);
        if (resolver == address(0)) {
            revert UnreachableName(name);
        }
        return _callResolver(resolver, name, call, true, context); // ==> step 3
    }

    /// @notice CCIP-Read callback for `_callResolver()` from batch calling the gasless DNS resolver.
    ///
    /// @param response The response data from the batch gateway.
    /// @param extraData The abi-encoded properties of the call.
    ///
    /// @return result The response from the resolver.
    function resolveBatchCallback(
        bytes calldata response,
        bytes calldata extraData
    ) external pure returns (bytes memory) {
        Lookup[] memory lookups = abi.decode(response, (Batch)).lookups;
        (bool multi, bool extended) = abi.decode(extraData, (bool, bool));
        if (multi) {
            bytes[] memory m = new bytes[](lookups.length);
            for (uint256 i; i < lookups.length; ++i) {
                Lookup memory lu = lookups[i];
                bytes memory v = lu.data;
                if (extended && (lu.flags & FLAGS_ANY_ERROR) == 0) {
                    v = abi.decode(v, (bytes)); // unwrap resolve()
                }
                m[i] = v;
            }
            return abi.encode(m);
        } else {
            Lookup memory lu = lookups[0];
            bytes memory v = lu.data;
            if ((lu.flags & FLAGS_ANY_ERROR) != 0) {
                assembly {
                    revert(add(v, 32), mload(v))
                }
            }
            if (extended) {
                v = abi.decode(v, (bytes)); // unwrap resolve()
            }
            return v;
        }
    }

    /// @notice CCIP-Read callback for `_callResolverDirect()`.
    function resolveDirectMulticallCallback(
        bytes calldata response,
        bytes calldata extraData
    ) external pure returns (bytes memory) {
        (bytes[] memory answers, uint256[] memory indexes) = abi.decode(
            extraData,
            (bytes[], uint256[])
        );
        // this is the encoded response of a function that returns (bytes)
        // this callback is only invoked if the calldata was a multicall
        bytes[] memory indexedAnswers = abi.decode(abi.decode(response, (bytes)), (bytes[]));
        if (indexes.length != indexedAnswers.length) {
            revert ArrayLengthMismatch(indexes.length, indexedAnswers.length);
        }
        for (uint256 i; i < indexes.length; ++i) {
            answers[indexes[i]] = indexedAnswers[i];
        }
        return abi.encode(answers);
    }

    ////////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////////

    /// @dev Determine underlying Mainnet resolver or null if not found.
    function _determineMainnetResolver(bytes memory name) internal view returns (address resolver) {
        (resolver, , ) = RegistryUtilsV1.findResolver(ENS_REGISTRY_V1, name, 0);
        if (resolver == DNS_TLD_RESOLVER_V1 || resolver == address(this)) {
            resolver = address(0);
        }
    }

    /// @dev Verify DNSSEC TXT record.
    function _verifyDNSSEC(
        bytes memory name,
        bytes calldata oracleWitness
    ) internal view returns (address resolver, bytes memory context) {
        DNSSEC.RRSetWithSignature[] memory rrsets = abi.decode(
            oracleWitness,
            (DNSSEC.RRSetWithSignature[])
        );
        (bytes memory data, ) = DNSSEC_ORACLE.verifyRRSet(rrsets);
        for (
            RRUtils.RRIterator memory iter = RRUtils.iterateRRs(data, 0);
            !RRUtils.done(iter);
            RRUtils.next(iter)
        ) {
            if (
                iter.class == CLASS_INET &&
                iter.dnstype == QTYPE_TXT &&
                BytesUtils.equals(iter.data, iter.offset, name, 0, name.length)
            ) {
                (resolver, context) = _parseTXT(
                    _readTXT(iter.data, iter.rdataOffset, iter.nextOffset)
                );
                if (resolver != address(0)) {
                    break;
                }
            }
        }
    }

    /// @dev Efficiently call another resolver with an optional DNS context.
    ///
    /// 1. if `IExtendedDNSResolver` and `hasContext`, `resolver.resolve(name, calldata, context)`.
    /// 2. if `IExtendedResolver`, `resolver.resolve(name, calldata)`.
    /// 3. otherwise, `resolver.staticall(calldata)`.
    ///
    /// - If (1) or (2), the calldata is not `multicall()`, and the resolver supports features,
    ///   the call is performed directly without the batch gateway.
    /// - If (1) or (2), the calldata is `multicall()`, and the resolver supports `RESOLVE_MULTICALL` feature,
    ///   the call is performed directly without the batch gateway.
    /// - Otherwise, the call is performed with the batch gateway.
    ///   If the calldata is `multicall()` it is disassembled, called separately, and reassembled.
    ///
    /// Reverts `UnreachableName` if resolver is not a contract.
    ///
    /// @param resolver The resolver to call.
    /// @param name The name to resolve.
    /// @param call The resolver calldata.
    /// @param hasContext True if `IExtendedDNSResolver` should be considered.
    /// @param context The context for `IExtendedDNSResolver`.
    function _callResolver(
        address resolver,
        bytes memory name,
        bytes memory call,
        bool hasContext,
        bytes memory context
    ) internal view returns (bytes memory result) {
        if (resolver.code.length == 0) {
            revert UnreachableName(name);
        }
        bool multi = bytes4(call) == IMulticallable.multicall.selector;
        bool direct = ERC165Checker.supportsERC165InterfaceUnchecked(
            resolver,
            type(IERC7996).interfaceId
        ) && (!multi || IERC7996(resolver).supportsFeature(ResolverFeatures.RESOLVE_MULTICALL));
        bool extendedDNS = hasContext &&
            ERC165Checker.supportsERC165InterfaceUnchecked(
                resolver,
                type(IExtendedDNSResolver).interfaceId
            );
        bool extended = extendedDNS ||
            ERC165Checker.supportsERC165InterfaceUnchecked(
                resolver,
                type(IExtendedResolver).interfaceId
            );
        bytes[] memory calls;
        if (multi) {
            calls = abi.decode(BytesUtils.substring(call, 4, call.length - 4), (bytes[]));
        } else {
            calls = new bytes[](1);
            calls[0] = call;
        }
        if (extended) {
            if (direct) {
                if (hasContext) {
                    return _callResolverDirect(resolver, name, calls, multi, extendedDNS, context);
                } else {
                    ccipRead(resolver, call);
                }
            }
            for (uint256 i; i < calls.length; ++i) {
                calls[i] = _makeExtendedCall(extendedDNS, name, calls[i], context);
            }
        }
        Batch memory batch = createBatch(resolver, calls, BATCH_GATEWAY_PROVIDER.gateways());
        for (uint256 i; i < calls.length; ++i) {
            Lookup memory lu = batch.lookups[i];
            bytes memory answer = _canAnswerCall(lu.call, context);
            if (answer.length > 0) {
                lu.flags = FLAG_DONE;
                lu.data = answer;
            }
        }
        ccipRead(
            address(this),
            abi.encodeCall(this.ccipBatch, (batch)),
            this.resolveBatchCallback.selector,
            IDENTITY_FUNCTION,
            abi.encode(multi, extended)
        );
    }

    /// @dev Call extended ENSIP-22 resolver.
    function _callResolverDirect(
        address resolver,
        bytes memory name,
        bytes[] memory calls,
        bool multi,
        bool extendedDNS,
        bytes memory context
    ) internal view returns (bytes memory result) {
        bytes[] memory answers = new bytes[](calls.length);
        uint256[] memory indexes = new uint256[](calls.length);
        bytes memory call;
        uint256 missing;
        for (uint256 i; i < calls.length; ++i) {
            call = calls[i];
            bytes memory answer = _canAnswerCall(call, context);
            if (answer.length > 0) {
                answers[i] = answer;
                continue;
            }
            bool ok;
            (ok, answer) = resolver.staticcall(_makeExtendedCall(extendedDNS, name, call, context));
            if (ok && answer.length >= 32) {
                answers[i] = abi.decode(answer, (bytes)); // unwrap resolve()
                continue;
            }
            indexes[missing++] = i;
        }
        if (missing == 0) {
            return multi ? abi.encode(answers) : answers[0]; // answer immediately
        }
        bool callback = missing < calls.length;
        if (callback) {
            for (uint256 i; i < missing; ++i) {
                calls[i] = calls[indexes[i]];
            }
            assembly {
                mstore(calls, missing) // truncate
                mstore(indexes, missing)
            }
        }
        call = multi ? abi.encodeCall(IMulticallable.multicall, (calls)) : calls[0];
        ccipRead(
            resolver,
            _makeExtendedCall(extendedDNS, name, call, context),
            callback ? this.resolveDirectMulticallCallback.selector : IDENTITY_FUNCTION,
            IDENTITY_FUNCTION,
            callback ? abi.encode(answers, indexes) : bytes("")
        );
    }

    /// @dev Parse the TXT record into resolver and context.
    ///      Format: "ENS1 <name-or-address> <context?>".
    ///
    /// @param txt The TXT data.
    ///
    /// @return resolver The resolver address or null if wrong format or name didn't resolve.
    /// @return context The optional context data.
    function _parseTXT(
        bytes memory txt
    ) internal view returns (address resolver, bytes memory context) {
        uint256 n = TXT_PREFIX.length;
        if (txt.length >= n && BytesUtils.equals(txt, 0, TXT_PREFIX, 0, n)) {
            uint256 sep = BytesUtils.find(txt, n, txt.length - n, " ");
            if (sep < txt.length) {
                context = BytesUtils.substring(txt, sep + 1, txt.length - sep - 1);
            } else {
                sep = txt.length;
            }
            resolver = _parseResolver(BytesUtils.substring(txt, n, sep - n));
        }
    }

    /// @dev Parse the value into a resolver address.
    ///      If the value matches `/^0x[0-9a-fA-F]{40}$/`, it's a literal address.
    ///      Otherwise, it's considered a name and resolved in the registry.
    ///      Reverts `DNSEncodingFailed` if the name cannot be encoded.
    ///
    /// @param v The address or name.
    ///
    /// @return resolver The corresponding resolver address.
    function _parseResolver(bytes memory v) internal view returns (address resolver) {
        if (v.length == 42 && v[0] == "0" && v[1] == "x") {
            (address addr, bool valid) = HexUtils.hexToAddress(v, 2, 42);
            if (valid) {
                return addr;
            }
        }
        bytes memory name = NameCoder.encode(string(v));
        (, address r, , ) = LibRegistry.findResolver(ROOT_REGISTRY, name, 0);
        if (r != address(0)) {
            // according to V1, this must be immediate onchain
            try IAddrResolver(r).addr(NameCoder.namehash(name, 0)) returns (address payable a) {
                resolver = a;
            } catch {}
        }
    }

    /// @dev Decode `v[off:end]` as raw TXT chunks.
    ///      Encoding: `(byte(n) <n-bytes>)...`
    ///      Reverts `InvalidTXT` if the data is malformed.
    ///
    /// @param v The raw TXT data.
    /// @param off The offset of the record data.
    /// @param end The upper bound of the record data.
    ///
    /// @return txt The decoded TXT value.
    function _readTXT(
        bytes memory v,
        uint256 off,
        uint256 end
    ) internal pure returns (bytes memory txt) {
        if (end > v.length) revert InvalidTXT();
        txt = new bytes(end - off);
        assembly {
            let ptr := add(v, 32)
            off := add(ptr, off) // start of input
            end := add(ptr, end) // end of input
            ptr := add(txt, 32) // start of output
            // prettier-ignore
            for { } lt(off, end) { } { // while input
                let size := byte(0, mload(off)) // length of chunk
                off := add(off, 1) // advance input
                if size { // length > 0
                    let next := add(off, size) // compute end of chunk
                    if gt(next, end) { // beyond end
                        end := 0 // error: overflow
                        break
                    }
                    mcopy(ptr, off, size) // copy chunk
                    off := next // advance input
                    ptr := add(ptr, size) // advance output
                }
            }
            mstore(txt, sub(ptr, add(txt, 32))) // truncate
        }
        if (off != end) revert InvalidTXT(); // overflow or junk at end
    }

    /// @dev Create extended resolver calldata.
    function _makeExtendedCall(
        bool extendedDNS,
        bytes memory name,
        bytes memory call,
        bytes memory context
    ) internal pure returns (bytes memory) {
        return
            extendedDNS
                ? abi.encodeCall(IExtendedDNSResolver.resolve, (name, call, context))
                : abi.encodeCall(IExtendedResolver.resolve, (name, call));
    }

    /// @dev Check if `call` should be answered by this resolver instead.
    function _canAnswerCall(
        bytes memory call,
        bytes memory context
    ) internal pure returns (bytes memory answer) {
        if (ResolverProfileDecoderLib.isText(call, keccak256(bytes(TEXT_KEY_DNSSEC_CONTEXT)))) {
            return abi.encode(context);
        }
    }
}
