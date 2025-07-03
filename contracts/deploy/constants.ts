export const MAX_EXPIRY = (1n << 64n) - 1n; // see: DatastoreUtils.sol

interface Flags {
  [key: string]: bigint | Flags;
}
const FLAGS = {
  // see: RegistryRolesMixin.sol
  EAC: {
    REGISTRAR: 0x1n,
    RENEW: 0x10n,
    SET_SUBREGISTRY: 0x100n,
    SET_RESOLVER: 0x1000n,
    SET_TOKEN_OBSERVER: 0x10000n,
  },
  // see: L2/ETHRegistry.sol
  ETH: {
    SET_PRICE_ORACLE: 0x100000n,
    SET_COMMITMENT_AGES: 0x1000000n,
  },
  // see: L2/UserRegistry.sol
  USER: {
    UPGRADE: 0x100000n,
  },
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
  ADMIN: Object.fromEntries(
    Object.entries(FLAGS).map(([k, v]) => [k, mapFlags(v, (x) => x << 128n)]),  
  ),
  ALL: 0x1111111111111111111111111111111111111111111111111111111111111111n, // see: EnhancedAccessControl.sol
  ADMIN_ROLES: 0x1111111111111111111111111111111100000000000000000000000000000000n, // see: EnhancedAccessControl.sol
} as const;
