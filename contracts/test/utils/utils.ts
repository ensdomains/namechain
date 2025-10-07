import { labelhash } from "viem";

// import type { ccipRequest } from "viem";
// export type CCIPReadOption =
//   | { request: typeof ccipRequest }
//   | undefined
//   | false;

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

// see: LibLabel.labelToCanonicalId()
export function labelToCanonicalId(label: string) {
  return getCanonicalId(BigInt(labelhash(label)));
}

// see: LibLabel.getCanonicalId
export function getCanonicalId(id: bigint) {
  return id ^ BigInt.asUintN(32, id);
}

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
