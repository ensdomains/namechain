import { keccak256, stringToBytes } from "viem";

export { dnsEncodeName } from "../../lib/ens-contracts/test/fixtures/dnsEncodeName.js";

// see: LibLabel.labelToCanonicalId()
export function labelToCanonicalId(label: string) {
  return getCanonicalId(BigInt(keccak256(stringToBytes(label))));
}

// see: LibLabel.getCanonicalId
export function getCanonicalId(id: bigint) {
  return id ^ BigInt.asUintN(32, id);
}

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
