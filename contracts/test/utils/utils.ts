import { labelhash, namehash } from "viem";

export {
  dnsEncodeName,
  packetToBytes,
  encodeLabelhash,
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

export const labelhashUint256 = (label: string): bigint => {
  return BigInt(labelhash(label));
};

export const namehashUint256 = (name: string): bigint => {
  return BigInt(namehash(name));
};

export function splitName(name: string): string[] {
  return name ? name.split(".") : [];
}
