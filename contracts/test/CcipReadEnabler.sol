// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {BytesUtils} from "@ens/contracts/utils/BytesUtils.sol";
import {EIP3668, OffchainLookup} from "@ens/contracts/ccipRead/EIP3668.sol";

library CcipReadEnabler {
    function enableCcipRead(address target) internal returns (address) {
        return address(new EnableCcipRead(target));
    }
}

contract EnableCcipRead {
    error HttpError(uint16 statusCode, string statusText);
    error MismatchingSenderAddress(address target, address sender);

    Vm internal constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    address _target;

    struct JsonResult {
        bytes data;
    }

    constructor(address target) {
        _target = target;
    }

    function _callAndFollow(
        bytes memory callData
    ) internal returns (bytes memory) {
        (bool ok, bytes memory data) = _target.call(callData);
        if (!ok && bytes4(data) == OffchainLookup.selector) {
            EIP3668.Params memory params = EIP3668.decode(
                BytesUtils.substring(data, 4, data.length - 4)
            );
            if (params.sender == _target) {
                bytes memory ccipReadResult = read(
                    params.sender,
                    params.urls,
                    params.callData
                );
                return
                    _callAndFollow(
                        abi.encodePacked(
                            params.callbackFunction,
                            abi.encode(ccipReadResult, params.extraData)
                        )
                    );
            } else revert MismatchingSenderAddress(_target, params.sender);
        }

        if (ok) {
            assembly {
                return(add(data, 32), mload(data))
            }
        } else {
            assembly {
                revert(add(data, 32), mload(data))
            }
        }
    }

    function read(
        address sender,
        string[] memory urls,
        bytes memory callData
    ) internal returns (bytes memory result) {
        for (uint256 i = 0; i < urls.length; i++) {
            string memory url = urls[i];
            bool useGet = vm.indexOf(url, "{data}") != type(uint256).max;
            string[] memory inputs = new string[](9);
            inputs[0] = "curl";
            inputs[1] = "-s";
            inputs[2] = "-X";

            if (!useGet) {
                string memory jsonId = vm.toString(
                    abi.encode(sender, urls, callData)
                );
                vm.serializeBytes(jsonId, "data", callData);
                inputs[3] = "POST";
                inputs[4] = "-H";
                inputs[5] = "Content-Type: application/json";
                inputs[6] = "-d";
                inputs[7] = vm.serializeAddress(jsonId, "sender", sender);
                inputs[8] = url;
            } else {
                url = vm.replace(url, "{data}", vm.toString(callData));
                url = vm.replace(url, "{sender}", vm.toString(sender));
                inputs[3] = "GET";
                inputs[4] = url;

                assembly {
                    mstore(inputs, 5)
                }
            }

            Vm.FfiResult memory ffiResult = vm.tryFfi(inputs);
            if (ffiResult.exitCode != 0) continue;
            // Try to parse the response as JSON first
            try vm.parseJson(string(ffiResult.stdout)) returns (
                bytes memory encodedResult
            ) {
                JsonResult memory jsonResult = abi.decode(
                    encodedResult,
                    (JsonResult)
                );
                return jsonResult.data;
            } catch {}
            return vm.parseBytes(string(ffiResult.stdout));
        }

        revert HttpError(500, "Failed to read from gateway");
    }

    fallback() external {
        _callAndFollow(msg.data);
    }
}
