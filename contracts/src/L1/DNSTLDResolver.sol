// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IExtendedResolver} from "@ens/contracts/resolvers/profiles/IExtendedResolver.sol";
import {IExtendedDNSResolver} from "@ens/contracts/resolvers/profiles/IExtendedDNSResolver.sol";
import {IUniversalResolver} from "@ens/contracts/universalResolver/IUniversalResolver.sol";
import {CCIPReader, OffchainLookup} from "@ens/contracts/ccipRead/CCIPReader.sol";
import {DNSSEC} from "@ens/contracts/dnssec-oracle/DNSSEC.sol";
import {RRUtils} from "@ens/contracts/dnssec-oracle/RRUtils.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {BytesUtils} from "@ens/contracts/utils/BytesUtils.sol";
import {HexUtils} from "@ens/contracts/utils/HexUtils.sol";

interface IDNSGateway {
    function resolve(
        bytes memory name,
        uint16 qtype
    ) external returns (DNSSEC.RRSetWithSignature[] memory);
}

uint16 constant CLASS_INET = 1;
uint16 constant TYPE_TXT = 16;

bytes constant PREFIX = "ENS1 ";
uint256 constant PREFIX_LENGTH = 5; // PREFIX.length

contract DNSTLDResolver is ERC165, CCIPReader, IExtendedResolver {
    /// @dev `name` does not exist.
    ///      Error selector: `0x5fe9a5df`
    /// @param name The DNS-encoded ENS name.
    error UnreachableName(bytes name);

    /// @dev Some raw TXT data was incorrectly encoded.
    ///      Error selector: `0xf4ba19b7`
    error InvalidTXT();

    IUniversalResolver public immutable universalResolverV1;
    IUniversalResolver public immutable universalResolverV2;
    DNSSEC public immutable oracleVerifier;
    string[] public oracleGateways;

    constructor(
        IUniversalResolver _universalResolverV1,
        IUniversalResolver _universalResolverV2,
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
            super.supportsInterface(interfaceId);
    }

    /// DNS Resolution with Fallback:
    /// 0. If there exists a resolver in V1, stop and use the V1 UR.
    /// 1. Query the DNSSEC oracle for TXT records.
    /// 2. Verify TXT records, parse ENS1 record into (resolver, context?), and query it based on its type.
    /// 3. Return the records.
    /// @notice Callers should enable EIP-3668.
    /// @dev This function executes over multiple steps (step 1 of 3).
    function resolve(
        bytes memory name,
        bytes calldata data
    ) external view returns (bytes memory) {
        (address resolver, , ) = universalResolverV1.findResolver(name);
        if (resolver != address(0)) {
            ccipRead(
                address(universalResolverV1),
                abi.encodeCall(IUniversalResolver.resolve, (name, data)),
                this.resolveV1Callback.selector,
                ""
            );
        } else {
            revert OffchainLookup(
                address(this),
                oracleGateways,
                abi.encodeCall(IDNSGateway.resolve, (name, TYPE_TXT)),
                this.resolveOracleCallback.selector,
                abi.encode(name, data)
            );
        }
    }

    /// @dev CCIP-Read callback for `resolve()` from calling `universalResolverV1` (step 2 of 2).
    /// @param response The response data.
    /// @return result The abi-encoded result.
    function resolveV1Callback(
        bytes calldata response,
        bytes calldata /*extraData*/
    ) external pure returns (bytes memory result) {
        (result, ) = abi.decode(response, (bytes, address));
    }

    /// @dev CCIP-Read callback for `resolve()` from calling the DNSSEC oracle (step 2 of 3).
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
            // Ignore records with wrong name, type, or class
            bytes memory rrname = RRUtils.readName(iter.data, iter.offset);
            if (
                !BytesUtils.equals(rrname, name) ||
                iter.class != CLASS_INET ||
                iter.dnstype != TYPE_TXT
            ) {
                continue;
            }

            // Look for a valid ENS-DNS TXT record
            (address resolver, bytes memory context) = _parseTXT(
                _readTXT(iter.data, iter.rdataOffset, iter.nextOffset)
            );
            if (resolver == address(0)) {
                continue;
            }

            // Call the resolver based on its type
            if (
                ERC165Checker.supportsERC165InterfaceUnchecked(
                    resolver,
                    type(IExtendedDNSResolver).interfaceId
                )
            ) {
                call = abi.encodeCall(
                    IExtendedDNSResolver.resolve,
                    (name, call, context)
                );
            } else if (
                ERC165Checker.supportsERC165InterfaceUnchecked(
                    resolver,
                    type(IExtendedResolver).interfaceId
                )
            ) {
                ccipRead(
                    resolver,
                    abi.encodeCall(IExtendedResolver.resolve, (name, call)),
                    this.resolveResolverCallback.selector,
                    '1'
                );
            }
            ccipRead(
                resolver,
                call,
                this.resolveResolverCallback.selector,
                call
            );
        }
        revert UnreachableName(name);
    }

    /// @dev CCIP-Read callback for `resolveOracleCallback()` from calling the DNS resolver (step 3 of 3).
    /// @param response The response data.
    /// @param extraData Non-null if the resolver was wildcard.
    /// @return result The abi-encoded result.
    function resolveResolverCallback(
        bytes calldata response,
        bytes calldata extraData
    ) external pure returns (bytes memory) {
        if (extraData.length > 0) {
            return abi.decode(response, (bytes)); // unwrap
        } else {
            return response;
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
            // find the first space after the resolver
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
                _trim(BytesUtils.substring(txt, PREFIX_LENGTH, sep))
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
