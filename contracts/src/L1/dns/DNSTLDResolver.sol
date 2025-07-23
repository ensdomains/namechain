// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {CCIPBatcher, CCIPReader, OffchainLookup} from "@ens/contracts/ccipRead/CCIPBatcher.sol";
import {DNSSEC} from "@ens/contracts/dnssec-oracle/DNSSEC.sol";
import {RRUtils} from "@ens/contracts/dnssec-oracle/RRUtils.sol";
import {RegistryUtils as RegistryUtilsV1, ENS} from "@ens/contracts/universalResolver/RegistryUtils.sol";
import {RegistryUtils, IRegistry} from "../../universalResolver/RegistryUtils.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {BytesUtils} from "@ens/contracts/utils/BytesUtils.sol";
import {HexUtils} from "@ens/contracts/utils/HexUtils.sol";
import {IFeatureSupporter} from "@ens/contracts/utils/IFeatureSupporter.sol";
import {ResolverFeatures} from "@ens/contracts/resolvers/ResolverFeatures.sol";

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
    ENS public immutable ensRegistryV1;
    address public immutable dnsTLDResolverV1;
    IRegistry public immutable rootRegistry;
    DNSSEC public immutable dnssecOracle;
    string[] _oracleGateways;
    string[] _batchGateways;

    /// @dev `name` does not exist.
    ///      Error selector: `0x5fe9a5df`
    /// @param name The DNS-encoded ENS name.
    error UnreachableName(bytes name);

    /// @dev Some raw TXT data was incorrectly encoded.
    ///      Error selector: `0xf4ba19b7`
    error InvalidTXT();

    constructor(
        ENS _ensRegistryV1,
        address _dnsTLDResolverV1,
        IRegistry _rootRegistry,
        DNSSEC _dnssecOracle,
        string[] memory __oracleGateways,
        string[] memory __batchGateways
    ) Ownable(msg.sender) CCIPReader(DEFAULT_UNSAFE_CALL_GAS) {
        ensRegistryV1 = _ensRegistryV1;
        dnsTLDResolverV1 = _dnsTLDResolverV1;
        rootRegistry = _rootRegistry;
        dnssecOracle = _dnssecOracle;
        _oracleGateways = __oracleGateways;
        _batchGateways = __batchGateways;
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
        _oracleGateways = gateways;
    }

    /// @notice Get the DNSSEC oracle gateways.
    /// @return The gateway URLs.
    function oracleGateways() external view returns (string[] memory) {
        return _oracleGateways;
    }

    /// @notice Set the batch gateways.
    /// @param gateways The batch gateway URLs.
    function setBatchGateways(string[] memory gateways) external onlyOwner {
        _batchGateways = gateways;
    }

    /// @notice Get the batch gateways.
    /// @return The batch gateway URLs.
    function batchGateways() external view returns (string[] memory) {
        return _batchGateways;
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
        (address resolver, , ) = RegistryUtilsV1.findResolver(
            ensRegistryV1,
            name,
            0
        );
        if (resolver != address(0) && resolver != dnsTLDResolverV1) {
            _callResolver(resolver, name, data, false, "");
        }
        revert OffchainLookup(
            address(this),
            _oracleGateways,
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
        (bytes memory data, ) = dnssecOracle.verifyRRSet(rrsets);
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

    /// @notice Efficiently call another resolver with an optional DNS context.
    ///
    /// 1. if `IExtendedDNSResolver` and `checkDNS`, `resolver.resolve(name, calldata, context)`.
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
    /// @dev Reverts `UnreachableName` if resolver is not a contract.
    /// @param resolver The resolver to call.
    /// @param name The name to resolve.
    /// @param call The resolver calldata.
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
            abi.encodeCall(
                this.ccipBatch,
                (createBatch(resolver, calls, _batchGateways))
            ),
            this.resolveBatchCallback.selector,
            IDENTITY_FUNCTION,
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

    /// @dev Parse the TXT record into resolver and context.
    ///      Format: "ENS1 <name-or-address> <context?>".
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
    ///      If the value matches `/^0x[0-9a-fA-F]{40}$/`, it's a literal address.
    ///      Otherwise, it's considered a name and resolved in the registry.
    ///      Reverts `DNSEncodingFailed` if the name cannot be encoded.
    /// @param v The address or name.
    /// @return resolver The corresponding resolver address.
    function _parseResolver(
        bytes memory v
    ) internal view returns (address resolver) {
        if (v.length == 42 && v[0] == "0" && v[1] == "x") {
            (address addr, bool valid) = HexUtils.hexToAddress(v, 2, 42);
            if (valid) {
                return addr;
            }
        }
        (, resolver, , ) = RegistryUtils.findResolver(
            rootRegistry,
            NameCoder.encode(string(v)),
            0
        );
    }

    /// @dev Decode `v[off:end]` as raw TXT chunks.
    ///      Encoding: `(byte(n) <n-bytes>)...`
    ///      Reverts `InvalidTXT` if the data is malformed.
    /// @param v The raw TXT data.
    /// @param off The offset of the record data.
    /// @param end The upper bound of the record data.
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
            off := add(ptr, off)
            end := add(ptr, end)
            ptr := add(txt, 32)
            // prettier-ignore
            for { } lt(off, end) { } {
                let size := byte(0, mload(off))
                off := add(off, 1)
                if size {
                    let next := add(off, size)
                    if gt(next, end) {
                        end := 0 // overflow
                        break
                    }
                    mcopy(ptr, off, size)
                    off := next
                    ptr := add(ptr, size)
                }
            }
            mstore(txt, sub(ptr, add(txt, 32))) // truncate
        }
        if (off != end) revert InvalidTXT(); // overflow or junk at end
    }
}
