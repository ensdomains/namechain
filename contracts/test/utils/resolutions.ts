import {
  type Hex,
  decodeFunctionResult,
  encodeFunctionData,
  encodeFunctionResult,
  getAddress,
  namehash,
  parseAbi,
} from "viem";
import { expect } from "vitest";

import {
  COIN_TYPE_ETH,
  shortCoin,
} from "../../lib/ens-contracts/test/fixtures/ensip19.js";

export * from "../../lib/ens-contracts/test/fixtures/ensip19.js";

export const MULTICALL_ABI = parseAbi([
  "function multicall(bytes[] calls) external view returns (bytes[])",
]);

export const ADDR_ABI = parseAbi([
  "function addr(bytes32) external view returns (address)",
  "function setAddr(bytes32, address) external",
]);

export const PROFILE_ABI = parseAbi([
  "function hasAddr(bytes32, uint256 coinType) external view returns (bool)",

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

export const DEDICATED_ABI = parseAbi([
  "function setAddr(uint256 coinType, bytes value) external",
  "function setText(string key, string value) external",
  "function setContenthash(bytes value) external",
  "function setPubkey(bytes32 x, bytes32 y) external",
  "function setName(string name) external",
  "function setABI(uint256 contentType, bytes data) external",
  "function setInterface(bytes4 interfaceID, address implementer) external",
]);

type StringRecord = { value: string };
type BytesRecord = { value: Hex };
export type HasAddressRecord = { coinType: bigint; exists: boolean };
export type PubkeyRecord = { x: Hex; y: Hex };
export type ErrorRecord = { call: Hex; answer: Hex };
export type TextRecord = StringRecord & { key: string };
export type AddressRecord = BytesRecord & { coinType: bigint };
export type ABIRecord = BytesRecord & { contentType: bigint };
export type InterfaceRecord = BytesRecord & { selector: Hex };

export type KnownProfile = {
  title?: string;
  name: string;
  extended?: boolean;
  addresses?: AddressRecord[];
  hasAddresses?: HasAddressRecord[];
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
  answer: Hex;
  expect(data: Hex): void;
  write: Hex;
  writeDedicated: Hex;
};

export type KnownResolution = Expected & {
  desc: string;
};

export type KnownBundle = Expected & {
  resolutions: KnownResolution[];
  unbundleAnswers: (data: Hex) => readonly Hex[];
};

export function bundleCalls(resolutions: KnownResolution[]): KnownBundle {
  if (resolutions.length == 1) {
    return {
      ...resolutions[0],
      resolutions,
      unbundleAnswers: (x) => [x],
    };
  }
  return {
    call: encodeFunctionData({
      abi: MULTICALL_ABI,
      args: [resolutions.map((x) => x.call)],
    }),
    answer: encodeFunctionResult({
      abi: MULTICALL_ABI,
      result: resolutions.map((x) => x.answer),
    }),
    resolutions,
    unbundleAnswers: (data) =>
      decodeFunctionResult({
        abi: MULTICALL_ABI,
        data,
      }),
    expect(answer) {
      const answers = this.unbundleAnswers(answer);
      expect(answers).toHaveLength(resolutions.length);
      resolutions.forEach((x, i) => x.expect(answers[i]));
    },
    write: encodeFunctionData({
      abi: MULTICALL_ABI,
      args: [resolutions.map((x) => x.write).filter((x) => x.length > 2)],
    }),
    writeDedicated: encodeFunctionData({
      abi: MULTICALL_ABI,
      args: [
        resolutions.map((x) => x.writeDedicated).filter((x) => x.length > 2),
      ],
    }),
  };
}

export function makeResolutions(p: KnownProfile): KnownResolution[] {
  const resolutions: KnownResolution[] = [];
  const node = namehash(p.name);
  if (p.addresses) {
    const functionName = "addr";
    for (const { coinType, value } of p.addresses) {
      if (coinType === COIN_TYPE_ETH) {
        const abi = ADDR_ABI;
        resolutions.push({
          desc: `${functionName}()`,
          call: encodeFunctionData({ abi, functionName, args: [node] }),
          answer: encodeFunctionResult({ abi, functionName, result: value }),
          expect(data) {
            const actual = decodeFunctionResult({ abi, functionName, data });
            expect(actual, this.desc).toStrictEqual(getAddress(value));
          },
          write: encodeFunctionData({
            abi,
            functionName: "setAddr",
            args: [node, value],
          }),
          writeDedicated: encodeFunctionData({
            abi: DEDICATED_ABI,
            functionName: "setAddr",
            args: [COIN_TYPE_ETH, value],
          }),
        });
      } else {
        const abi = PROFILE_ABI;
        resolutions.push({
          desc: `${functionName}(${shortCoin(coinType)})`,
          call: encodeFunctionData({
            abi,
            functionName,
            args: [node, coinType],
          }),
          answer: encodeFunctionResult({ abi, functionName, result: value }),
          expect(data) {
            const actual = decodeFunctionResult({ abi, functionName, data });
            expect(actual, this.desc).toStrictEqual(value.toLowerCase());
          },
          write: encodeFunctionData({
            abi,
            functionName: "setAddr",
            args: [node, coinType, value],
          }),
          writeDedicated: encodeFunctionData({
            abi: DEDICATED_ABI,
            functionName: "setAddr",
            args: [coinType, value],
          }),
        });
      }
    }
  }
  if (p.hasAddresses) {
    const abi = PROFILE_ABI;
    const functionName = "hasAddr";
    for (const { coinType, exists } of p.hasAddresses) {
      resolutions.push({
        desc: `${functionName}(${shortCoin(coinType)})`,
        call: encodeFunctionData({
          abi,
          functionName,
          args: [node, coinType],
        }),
        answer: encodeFunctionResult({ abi, functionName, result: exists }),
        expect(data) {
          const actual = decodeFunctionResult({ abi, functionName, data });
          expect(actual, this.desc).toStrictEqual(exists);
        },
        write: "0x",
        writeDedicated: "0x",
      });
    }
  }
  if (p.texts) {
    const abi = PROFILE_ABI;
    const functionName = "text";
    for (const { key, value } of p.texts) {
      resolutions.push({
        desc: `${functionName}(${key})`,
        call: encodeFunctionData({ abi, functionName, args: [node, key] }),
        answer: encodeFunctionResult({ abi, functionName, result: value }),
        expect(data) {
          const actual = decodeFunctionResult({ abi, functionName, data });
          expect(actual, this.desc).toStrictEqual(value);
        },
        write: encodeFunctionData({
          abi,
          functionName: "setText",
          args: [node, key, value],
        }),
        writeDedicated: encodeFunctionData({
          abi: DEDICATED_ABI,
          functionName: "setText",
          args: [key, value],
        }),
      });
    }
  }
  if (p.contenthash) {
    const abi = PROFILE_ABI;
    const functionName = "contenthash";
    const { value } = p.contenthash;
    resolutions.push({
      desc: `${functionName}()`,
      call: encodeFunctionData({ abi, functionName, args: [node] }),
      answer: encodeFunctionResult({ abi, functionName, result: value }),
      expect(data) {
        const actual = decodeFunctionResult({ abi, functionName, data });
        expect(actual, this.desc).toStrictEqual(value);
      },
      write: encodeFunctionData({
        abi,
        functionName: "setContenthash",
        args: [node, value],
      }),
      writeDedicated: encodeFunctionData({
        abi: DEDICATED_ABI,
        functionName: "setContenthash",
        args: [value],
      }),
    });
  }
  if (p.pubkey) {
    const abi = PROFILE_ABI;
    const functionName = "pubkey";
    const { x, y } = p.pubkey;
    resolutions.push({
      desc: `${functionName}()`,
      call: encodeFunctionData({ abi, functionName, args: [node] }),
      answer: encodeFunctionResult({ abi, functionName, result: [x, y] }),
      expect(data) {
        const actual = decodeFunctionResult({ abi, functionName, data });
        expect(actual, this.desc).toStrictEqual([x, y]);
      },
      write: encodeFunctionData({
        abi,
        functionName: "setPubkey",
        args: [node, x, y],
      }),
      writeDedicated: encodeFunctionData({
        abi: DEDICATED_ABI,
        functionName: "setPubkey",
        args: [x, y],
      }),
    });
  }
  if (p.primary) {
    const abi = PROFILE_ABI;
    const functionName = "name";
    const { value } = p.primary;
    resolutions.push({
      desc: `${functionName}()`,
      call: encodeFunctionData({ abi, functionName, args: [node] }),
      answer: encodeFunctionResult({ abi, functionName, result: value }),
      expect(data) {
        const actual = decodeFunctionResult({ abi, functionName, data });
        expect(actual, this.desc).toStrictEqual(value);
      },
      write: encodeFunctionData({
        abi,
        functionName: "setName",
        args: [node, value],
      }),
      writeDedicated: encodeFunctionData({
        abi: DEDICATED_ABI,
        functionName: "setName",
        args: [value],
      }),
    });
  }
  if (p.abis) {
    const abi = PROFILE_ABI;
    const functionName = "ABI";
    for (const { contentType, value } of p.abis) {
      resolutions.push({
        desc: `${functionName}(${contentType})`,
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
        write: encodeFunctionData({
          abi,
          functionName: "setABI",
          args: [node, contentType, value],
        }),
        writeDedicated: encodeFunctionData({
          abi: DEDICATED_ABI,
          functionName: "setABI",
          args: [contentType, value],
        }),
      });
    }
  }
  if (p.interfaces) {
    const abi = PROFILE_ABI;
    const functionName = "interfaceImplementer";
    for (const { selector, value } of p.interfaces) {
      resolutions.push({
        desc: `${functionName}(${selector})`,
        call: encodeFunctionData({ abi, functionName, args: [node, selector] }),
        answer: encodeFunctionResult({ abi, functionName, result: value }),
        expect(data) {
          const actual = decodeFunctionResult({ abi, functionName, data });
          expect(actual, this.desc).toStrictEqual(value);
        },
        write: encodeFunctionData({
          abi,
          functionName: "setInterface",
          args: [node, selector, value],
        }),
        writeDedicated: encodeFunctionData({
          abi: DEDICATED_ABI,
          functionName: "setInterface",
          args: [selector, value],
        }),
      });
    }
  }
  if (p.errors) {
    for (const { call, answer } of p.errors) {
      resolutions.push({
        desc: `error(${call.slice(0, 10)})`,
        call,
        answer,
        expect(data) {
          expect(data, this.desc).toStrictEqual(this.answer);
        },
        write: "0x",
        writeDedicated: "0x",
      });
    }
  }
  return resolutions;
}
