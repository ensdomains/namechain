export const MAX_EXPIRY = (1n << 64n) - 1n; // see: DatastoreUtils.sol

interface Flags {
  [key: string]: bigint | Flags;
}
const FLAGS = {
  // see: RegistryRolesMixin.sol
  EAC: {
    REGISTRAR: 1n << 0n,
    RENEW: 1n << 1n,
    SET_SUBREGISTRY: 1n << 2n,
    SET_RESOLVER: 1n << 3n,
    SET_TOKEN_OBSERVER: 1n << 4n,
  },
  // see: L2/ETHRegistry.sol
  ETH: {
    SET_PRICE_ORACLE: 1n << 0n,
    SET_COMMITMENT_AGES: 1n << 1n,
  },
  // see: L2/UserRegistry.sol
  USER: {
    UPGRADE: 1n << 5n,
  },
  MASK: (1n << 128n) - 1n,
} as const satisfies Flags;
function mapFlags(flags: Flags, fn: (x: bigint) => bigint): Flags {
  return Object.fromEntries(
    Object.entries(flags).map(([k, x]) => [
      k,
      typeof x === "bigint" ? fn(x) : mapFlags(x, fn),
    ]),
  );
}
export const ROLES = {
  OWNER: FLAGS,
  ADMIN: mapFlags(FLAGS, (x) => x << 128n),
  ALL: (1n << 256n) - 1n, // see: EnhancedAccessControl.sol
} as const;
