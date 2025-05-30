// import { labelhash, namehash } from "viem";

import type { Fixture } from "@nomicfoundation/hardhat-network-helpers/types";
import type {
  DefaultChainType,
  NetworkConnection,
} from "hardhat/types/network";

export { expectVar } from "../../lib/ens-contracts/test/fixtures/expectVar.js";

export {
  dnsEncodeName,
  encodeLabelhash,
  packetToBytes,
} from "../../lib/ens-contracts/test/fixtures/dnsEncodeName.js";

// export function packetToBytes(packet: string) {
//   const m = splitName(packet).flatMap(s => {
//   let v = stringToBytes(s);
//   if (v.length > 255) v = stringToBytes(`[${labelhash(s).slice(2)}]`);
//     return [Uint8Array.of(v.length), v];
//   });
//   m.push(Uint8Array.of(0));
//   return concat(m);
// }

// export function dnsEncodeName(name: string) {
//   return bytesToHex(packetToBytes(name));
// }

// export const labelhashUint256 = (label: string): bigint => {
//   return BigInt(labelhash(label));
// };

// export const namehashUint256 = (name: string): bigint => {
//   return BigInt(namehash(name));
// };

//      "" => []
// "a.b.c" => ["a", "b", "c"]
export function splitName(name: string): string[] {
  return name ? name.split(".") : [];
}

//      "" => ""
// "a.b.c" => "b.c"
export function getParentName(name: string) {
  const i = name.indexOf(".");
  return i == -1 ? "" : name.slice(i + 1);
}

// "a.b.c"  0 => "a"
//         -1 => "c"
//          5 => ""
export function getLabelAt(name: string, index: number) {
  return splitName(name).at(index) ?? "";
}

export function createFixture<T>(
  networkConnection: NetworkConnection<DefaultChainType>,
  fixture: (n: NetworkConnection<DefaultChainType>) => Fixture<T>,
) {
  const initialisedFixture = fixture(networkConnection);
  return async () =>
    networkConnection.networkHelpers.loadFixture(initialisedFixture);
}
