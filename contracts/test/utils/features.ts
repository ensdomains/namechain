import { keccak256, slice, stringToHex } from "viem";

export function makeFeature(s: string) {
  return slice(keccak256(stringToHex(s)), 0, 6);
}

export const FEATURES = {
  RESOLVER: {
    RESOLVE_MULTICALL: makeFeature("ens.resolver.extended.multicall"),
    DEDICATED: makeFeature("ens.resolver.dedicated"),
  },
} as const;
