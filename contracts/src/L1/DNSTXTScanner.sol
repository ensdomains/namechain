// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {BytesUtils} from "@ens/contracts/utils/BytesUtils.sol";

/// @title DNSTXTScanner
/// @dev Library for parsing record data from DNS TXT records.
///
///  The record data consists of a series of key=value pairs, separated by spaces. Keys
///  may have an optional argument in square brackets, and values may be either unquoted
///   - in which case they may not contain spaces - or single-quoted. Single quotes in
///  a quoted value may be backslash-escaped.
///
///  eg. `a=x`, `a[]=x`, `a[b]=x`, `a[b]='x y'`, `a[b]='x y\'s'`
///
///    ┌───────────────────────────────────────────────────────────────────────────────────────────┐
///    │  ┌───◄───┐                                                                                │
///    │  │ ┌───┐ │  ┌───┐    ┌───┐    ┌───┐    ┌───┐    ┌───┐    ┌───┐    ┌────────────┐    ┌───┐ │
///  ^─┴─►┴─┤" "│─┴─►│key├─┬─►│"["├───►│arg├───►│"]"├─┬─►│"="├─┬─►│"'"├───►│quoted_value├───►│"'"├─┼─$
///         └───┘    └───┘ │  └───┘    └───┘    └───┘ │  └───┘ │  └───┘    └────────────┘    └───┘ │
///                        └──────────────────────────┘        │          ┌──────────────┐         │
///                                                            └─────────►│unquoted_value├─────────┘
///                                                                       └──────────────┘

library DNSTXTScanner {
    /// @dev The DFA internal states.
    enum State {
        START,
        IGNORED_KEY,
        IGNORED_KEY_ARG,
        VALUE,
        QUOTED_VALUE,
        UNQUOTED_VALUE,
        IGNORED_VALUE,
        IGNORED_QUOTED_VALUE,
        IGNORED_UNQUOTED_VALUE
    }

    /// @dev Implements a DFA to parse the text record, looking for an entry matching `key`.
    /// @param data The text record to parse.
    /// @param key The exact key to search for with trailing equals, eg. "key=".
    /// @return value The value if found, or an empty string if `key` does not exist.
    function find(
        bytes memory data,
        bytes memory key
    ) internal pure returns (bytes memory value) {
        // Here we use a simple state machine to parse the text record. We
        // process characters one at a time; each character can trigger a
        // transition to a new state, or terminate the DFA and return a value.
        // For states that expect to process a number of tokens, we use
        // inner loops for efficiency reasons, to avoid the need to go
        // through the outer loop and switch statement for every character.
        State state = State.START;
        uint256 len = data.length;
        for (uint256 i; i < len; ) {
            if (state == State.START) {
                while (i < len && data[i] == " ") {
                    i += 1;
                }
                if (i + key.length > len) {
                    break;
                } else if (BytesUtils.equals(data, i, key, 0, key.length)) {
                    i += key.length;
                    state = State.VALUE;
                } else {
                    state = State.IGNORED_KEY;
                }
            } else if (state == State.IGNORED_KEY) {
                for (; i < len; i++) {
                    if (data[i] == "=") {
                        state = State.IGNORED_VALUE;
                    } else if (data[i] == "[") {
                        state = State.IGNORED_KEY_ARG;
                    } else if (data[i] == " ") {
                        state = State.START;
                    } else {
                        continue;
                    }
                    i += 1;
                    break;
                }
            } else if (state == State.IGNORED_KEY_ARG) {
                for (; i < len; i++) {
                    if (data[i] == "]") {
                        i += 1;
                        if (i < len && data[i] == "=") {
                            state = State.IGNORED_VALUE;
                            i += 1;
                        } else {
                            state = State.IGNORED_UNQUOTED_VALUE;
                        }
                        break;
                    }
                }
            } else if (state == State.VALUE) {
                if (data[i] == "'") {
                    state = State.QUOTED_VALUE;
                    i += 1;
                } else {
                    state = State.UNQUOTED_VALUE;
                }
            } else if (state == State.QUOTED_VALUE) {
                uint256 valueLen;
                bool escaped;
                for (uint256 start = i; i < len; i++) {
                    if (escaped) {
                        data[start + valueLen] = data[i];
                        valueLen += 1;
                        escaped = false;
                    } else {
                        if (data[i] == "\\") {
                            escaped = true;
                        } else if (data[i] == "'") {
                            return BytesUtils.substring(data, start, valueLen);
                        } else {
                            data[start + valueLen] = data[i];
                            valueLen += 1;
                        }
                    }
                }
            } else if (state == State.UNQUOTED_VALUE) {
                for (uint256 j = i; j < len; j++) {
                    if (data[j] == " ") {
                        len = j;
                    }
                }
                return BytesUtils.substring(data, i, len - i);
            } else if (state == State.IGNORED_VALUE) {
                if (data[i] == "'") {
                    state = State.IGNORED_QUOTED_VALUE;
                    i += 1;
                } else {
                    state = State.IGNORED_UNQUOTED_VALUE;
                }
            } else if (state == State.IGNORED_QUOTED_VALUE) {
                bool escaped = false;
                for (; i < len; i++) {
                    if (escaped) {
                        escaped = false;
                    } else {
                        if (data[i] == "\\") {
                            escaped = true;
                        } else if (data[i] == "'") {
                            i += 1;
                            state = State.START;
                            break;
                        }
                    }
                }
            } else {
                assert(state == State.IGNORED_UNQUOTED_VALUE);
                if (data[i] == " ") {
                    state = State.START;
                }
                i += 1;
            }
        }
    }
}
