import { labelhash } from "viem";

export { dnsEncodeName } from "../../lib/ens-contracts/test/fixtures/dnsEncodeName.js";

export function labelId(label: string): bigint {
  return BigInt(labelhash(label));
}

export function constructId(id: bigint, version = 0) {
  return id ^ BigInt.asUintN(32, id ^ BigInt(version));
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

// "a.b.c"  0 => "a" aka firstLabel()
//         -1 => "c"
//          5 => ""
export function getLabelAt(name: string, index = 0) {
  return splitName(name).at(index) ?? "";
}
