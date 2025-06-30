// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {BytesUtils} from "@ens/contracts/utils/BytesUtils.sol";

/// @title DNSTXTScanner
/// @dev Library for parsing ENS records from DNS TXT data.
///
/// The record data consists of a series of key=value pairs, separated by spaces. Keys
/// may have an optional argument in square brackets, and values may be either unquoted
/// - in which case they may not contain spaces - or single-quoted. Single quotes in
/// a quoted value may be backslash-escaped.
///
/// eg. `a=x`, `a[]=x`, `a[b]=x`, `a[b]='x y'`, `a[b]='x y\'s'`
///
/// <records> ::= " "* <rr>* " "*
///      <rr> ::= <r> | <r> <rr>
///       <r> ::= <pk> | <kv>
///      <pk> ::= <u> | <u> "[" <a> "]" <u>
///      <kv> ::= <k> "=" <v>
///       <k> ::= <u> | <u> "[" <a> "]"
///       <v> ::= "'" <q> "'" | <u>
///       <q> ::= <all octets except "'" unless preceeded by "\">
///       <u> ::= <all octets except " ">
///       <a> ::= <all octets except "]">
///
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

    bytes1 constant CH_BACKSLASH = bytes1(0x5C); // "\"
    bytes1 constant CH_QUOTE = "'";
    bytes1 constant CH_SPACE = " ";
    bytes1 constant CH_EQUAL = "=";
    bytes1 constant CH_ARG_OPEN = "[";
    bytes1 constant CH_ARG_CLOSE = "]";

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
                while (i < len && data[i] == CH_SPACE) {
                    ++i;
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
                while (i < len) {
                    bytes1 cp = data[i++];
                    if (cp == CH_EQUAL) {
                        state = State.IGNORED_VALUE;
                        break;
                    } else if (cp == CH_ARG_OPEN) {
                        state = State.IGNORED_KEY_ARG;
                        break;
                    } else if (cp == CH_SPACE) {
                        state = State.START;
                        break;
                    }
                }
            } else if (state == State.IGNORED_KEY_ARG) {
                for (; i < len; ++i) {
                    if (data[i] == CH_ARG_CLOSE) {
                        ++i;
                        if (i < len && data[i] == CH_EQUAL) {
                            state = State.IGNORED_VALUE;
                            ++i;
                        } else {
                            state = State.IGNORED_UNQUOTED_VALUE;
                        }
                        break;
                    }
                }
            } else if (state == State.VALUE) {
                if (data[i] == CH_QUOTE) {
                    state = State.QUOTED_VALUE;
                    ++i;
                } else {
                    state = State.UNQUOTED_VALUE;
                }
            } else if (state == State.QUOTED_VALUE) {
                uint256 n;
                for (uint256 j = i; i < len; ++n) {
                    bytes1 cp = data[i++];
                    if (cp == CH_QUOTE) {
                        value = new bytes(n);
                        for (i = 0; i < n; ++i) {
                            cp = data[j++];
                            if (cp == CH_BACKSLASH) {
                                cp = data[j++];
                            }
                            value[i] = cp;
                        }
                        return value;
                    } else if (cp == CH_BACKSLASH) {
                        ++i;
                    }
                }
            } else if (state == State.UNQUOTED_VALUE) {
                for (uint256 j = i; j < len; ++j) {
                    if (data[j] == CH_SPACE) {
                        len = j;
                    }
                }
                return BytesUtils.substring(data, i, len - i);
            } else if (state == State.IGNORED_VALUE) {
                if (data[i] == CH_QUOTE) {
                    state = State.IGNORED_QUOTED_VALUE;
                    ++i;
                } else {
                    state = State.IGNORED_UNQUOTED_VALUE;
                }
            } else if (state == State.IGNORED_QUOTED_VALUE) {
                while (i < len) {
                    bytes1 cp = data[i++];
                    if (cp == CH_QUOTE) {
                        break;
                    } else if (cp == CH_BACKSLASH) {
                        ++i;
                    }
                }
                state = State.START;
            } else {
                // state = State.IGNORED_UNQUOTED_VALUE
                if (data[i] == CH_SPACE) {
                    state = State.START;
                }
                ++i;
            }
        }
    }
}
