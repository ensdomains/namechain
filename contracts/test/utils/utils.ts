import { labelhash } from "viem";

// import type { ccipRequest } from "viem";
// export type CCIPReadOption =
//   | { request: typeof ccipRequest }
//   | undefined
//   | false;

export { dnsEncodeName } from "../../lib/ens-contracts/test/fixtures/dnsEncodeName.js";

// see: NameUtils.labelToCanonicalId()
export function labelToCanonicalId(label: string) {
  return getCanonicalId(BigInt(labelhash(label)));
}

// see: NameUtils.getCanonicalId
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

// "a.b.c"  0 => "a" aka firstLabel()
//         -1 => "c"
//          5 => ""
export function getLabelAt(name: string, index = 0) {
  return splitName(name).at(index) ?? "";
}
