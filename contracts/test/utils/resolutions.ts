import { expect } from "chai";
import {
  type Hex,
  decodeFunctionResult,
  encodeFunctionData,
  encodeFunctionResult,
  getAddress,
  namehash,
  parseAbi,
} from "viem";
import {
  COIN_TYPE_ETH,
  shortCoin,
} from "../../lib/ens-contracts/test/fixtures/ensip19.js";

export * from "../../lib/ens-contracts/test/fixtures/ensip19.js";

export const RESOLVE_MULTICALL = parseAbi([
  "function multicall(bytes[] calls) external view returns (bytes[])",
]);

export const ADDR_ABI = parseAbi([
  "function addr(bytes32) external view returns (address)",
  "function setAddr(bytes32, address) external",
]);

export const PROFILE_ABI = parseAbi([
  "function recordVersions(bytes32) external view returns (uint64)",

  "function addr(bytes32, uint256 coinType) external view returns (bytes)",
  "function setAddr(bytes32, uint256 coinType, bytes value) external",

  "function text(bytes32, string key) external view returns (string)",
  "function setText(bytes32, string key, string value) external",

  "function contenthash(bytes32) external view returns (bytes)",
  "function setContenthash(bytes32, bytes value) external",

  "function pubkey(bytes32) external view returns (bytes32, bytes32)",
  "function setPubkey(bytes32, bytes32 x, bytes32 y) external",

  "function name(bytes32) external view returns (string)",
  "function setName(bytes32, string name) external",

  "function ABI(bytes32, uint256 contentTypes) external view returns (uint256, bytes memory)",
  "function setABI(bytes32, uint256 contentType, bytes data) external",

  "function interfaceImplementer(bytes32, bytes4 interfaceID) external view returns (address)",
  "function setInterface(bytes32, bytes4 interfaceID, address implementer) external",
]);

// see: CCIPBatcher.sol
export const RESPONSE_FLAGS = {
  OFFCHAIN: 1n << 0n,
  CALL_ERROR: 1n << 1n,
  BATCH_ERROR: 1n << 2n,
  EMPTY_RESPONSE: 1n << 3n,
  EIP140_BEFORE: 1n << 4n,
  EIP140_AFTER: 1n << 5n,
  DONE: 1n << 6n,
} as const;

type KnownOrigin = "on" | "off" | "batch";

type OriginRecord = { origin?: KnownOrigin };
type StringRecord = OriginRecord & { value: string };
type BytesRecord = OriginRecord & { value: Hex };
type PubkeyRecord = OriginRecord & { x: Hex; y: Hex };
type ErrorRecord = OriginRecord & { call: Hex; answer: Hex };
type AddressRecord = BytesRecord & { coinType: bigint };
type TextRecord = StringRecord & { key: string };
type ABIRecord = BytesRecord & { contentType: bigint };
type InterfaceRecord = BytesRecord & { selector: Hex };

export type KnownProfile = {
  title?: string;
  name: string;
  extended?: boolean;
  addresses?: AddressRecord[];
  texts?: TextRecord[];
  contenthash?: BytesRecord;
  primary?: StringRecord;
  pubkey?: PubkeyRecord;
  interfaces?: InterfaceRecord[];
  abis?: ABIRecord[];
  errors?: ErrorRecord[];
};

export type KnownReverse = {
  title: string;
  expectError?: boolean;
  encodedAddress: Hex;
  coinType: bigint;
  expectPrimary?: boolean;
};

type Expected = {
  call: Hex;
  write: Hex;
  answer: Hex;
  expect(data: Hex): void;
};

export type KnownResolution = Expected & {
  desc: string;
  origin?: KnownOrigin;
};

export type KnownBundle = Expected & {
  unbundle: (data: Hex) => readonly Hex[];
};

export function bundleCalls(resolutions: KnownResolution[]): KnownBundle {
  if (resolutions.length == 1) {
    return {
      ...resolutions[0],
      unbundle: (x) => [x],
    };
  }
  return {
    write: encodeFunctionData({
      abi: RESOLVE_MULTICALL,
      args: [resolutions.map((x) => x.write)],
    }),
    call: encodeFunctionData({
      abi: RESOLVE_MULTICALL,
      args: [resolutions.map((x) => x.call)],
    }),
    answer: encodeFunctionResult({
      abi: RESOLVE_MULTICALL,
      result: resolutions.map((x) => x.answer),
    }),
    unbundle: (data) =>
      decodeFunctionResult({
        abi: RESOLVE_MULTICALL,
        data,
      }),
    expect(answer) {
      const answers = this.unbundle(answer);
      expect(answers).toHaveLength(resolutions.length);
      resolutions.forEach((x, i) => x.expect(answers[i]));
    },
  };
}

export function makeResolutions(p: KnownProfile): KnownResolution[] {
  const resolutions: KnownResolution[] = [];
  const node = namehash(p.name);
  if (p.addresses) {
    const functionName = "addr";
    for (const { coinType, value, origin } of p.addresses) {
      if (coinType === COIN_TYPE_ETH) {
        const abi = ADDR_ABI;
        resolutions.push({
          desc: `${functionName}()`,
          origin,
          write: encodeFunctionData({
            abi,
            functionName: "setAddr",
            args: [node, value],
          }),
          call: encodeFunctionData({ abi, functionName, args: [node] }),
          answer: encodeFunctionResult({ abi, functionName, result: value }),
          expect(data) {
            const actual = decodeFunctionResult({ abi, functionName, data });
            expect(actual, this.desc).toStrictEqual(getAddress(value));
          },
        });
      } else {
        const abi = PROFILE_ABI;
        resolutions.push({
          desc: `${functionName}(${shortCoin(coinType)})`,
          origin,
          write: encodeFunctionData({
            abi,
            functionName: "setAddr",
            args: [node, coinType, value],
          }),
          call: encodeFunctionData({
            abi,
            functionName,
            args: [node, coinType],
          }),
          answer: encodeFunctionResult({ abi, functionName, result: value }),
          expect(data) {
            const actual = decodeFunctionResult({ abi, functionName, data });
            expect(actual, this.desc).toStrictEqual(value);
          },
        });
      }
    }
  }
  if (p.texts) {
    const abi = PROFILE_ABI;
    const functionName = "text";
    for (const { key, value, origin } of p.texts) {
      resolutions.push({
        desc: `${functionName}(${key})`,
        origin,
        write: encodeFunctionData({
          abi,
          functionName: "setText",
          args: [node, key, value],
        }),
        call: encodeFunctionData({ abi, functionName, args: [node, key] }),
        answer: encodeFunctionResult({ abi, functionName, result: value }),
        expect(data) {
          const actual = decodeFunctionResult({ abi, functionName, data });
          expect(actual, this.desc).toStrictEqual(value);
        },
      });
    }
  }
  if (p.contenthash) {
    const abi = PROFILE_ABI;
    const functionName = "contenthash";
    const { value, origin } = p.contenthash;
    resolutions.push({
      desc: `${functionName}()`,
      origin,
      write: encodeFunctionData({
        abi,
        functionName: "setContenthash",
        args: [node, value],
      }),
      call: encodeFunctionData({ abi, functionName, args: [node] }),
      answer: encodeFunctionResult({ abi, functionName, result: value }),
      expect(data) {
        const actual = decodeFunctionResult({ abi, functionName, data });
        expect(actual, this.desc).toStrictEqual(value);
      },
    });
  }
  if (p.pubkey) {
    const abi = PROFILE_ABI;
    const functionName = "pubkey";
    const { x, y, origin } = p.pubkey;
    resolutions.push({
      desc: `${functionName}()`,
      origin,
      write: encodeFunctionData({
        abi,
        functionName: "setPubkey",
        args: [node, x, y],
      }),
      call: encodeFunctionData({ abi, functionName, args: [node] }),
      answer: encodeFunctionResult({ abi, functionName, result: [x, y] }),
      expect(data) {
        const actual = decodeFunctionResult({ abi, functionName, data });
        expect(actual, this.desc).toStrictEqual([x, y]);
      },
    });
  }
  if (p.primary) {
    const abi = PROFILE_ABI;
    const functionName = "name";
    const { value, origin } = p.primary;
    resolutions.push({
      desc: `${functionName}()`,
      origin,
      write: encodeFunctionData({
        abi,
        functionName: "setName",
        args: [node, value],
      }),
      call: encodeFunctionData({ abi, functionName, args: [node] }),
      answer: encodeFunctionResult({ abi, functionName, result: value }),
      expect(data) {
        const actual = decodeFunctionResult({ abi, functionName, data });
        expect(actual, this.desc).toStrictEqual(value);
      },
    });
  }
  if (p.abis) {
    const abi = PROFILE_ABI;
    const functionName = "ABI";
    for (const { contentType, value, origin } of p.abis) {
      resolutions.push({
        desc: `${functionName}(${contentType})`,
        origin,
        write: encodeFunctionData({
          abi,
          functionName: "setABI",
          args: [node, contentType, value],
        }),
        call: encodeFunctionData({
          abi,
          functionName,
          args: [node, contentType],
        }),
        answer: encodeFunctionResult({
          abi,
          functionName,
          result: [contentType, value],
        }),
        expect(data) {
          const actual = decodeFunctionResult({ abi, functionName, data });
          expect(actual, this.desc).toStrictEqual([contentType, value]);
        },
      });
    }
  }
  if (p.interfaces) {
    const abi = PROFILE_ABI;
    const functionName = "interfaceImplementer";
    for (const { selector, value, origin } of p.interfaces) {
      resolutions.push({
        desc: `${functionName}(${selector})`,
        origin,
        write: encodeFunctionData({
          abi,
          functionName: "setInterface",
          args: [node, selector, value],
        }),
        call: encodeFunctionData({ abi, functionName, args: [node, selector] }),
        answer: encodeFunctionResult({ abi, functionName, result: value }),
        expect(data) {
          const actual = decodeFunctionResult({ abi, functionName, data });
          expect(actual, this.desc).toStrictEqual(value);
        },
      });
    }
  }
  if (p.errors) {
    for (const { call, answer } of p.errors) {
      resolutions.push({
        desc: `error(${call.slice(0, 10)})`,
        write: "0x",
        call,
        answer,
        expect(data) {
          expect(data, this.desc).toStrictEqual(this.answer);
        },
      });
    }
  }
  return resolutions;
}
