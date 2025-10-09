export const MAX_EXPIRY = (1n << 64n) - 1n; // see: DatastoreUtils.sol

export const LOCAL_BATCH_GATEWAY_URL = "x-batch-gateway:true";

interface Flags {
  [key: string]: bigint | Flags;
}
const OWNER = {
  // see: RegistryRolesLib.sol
  REGISTRY: {
    REGISTRAR: 1n << 0n,
    RENEW: 1n << 4n,
    SET_SUBREGISTRY: 1n << 8n,
    SET_RESOLVER: 1n << 12n,
    SET_TOKEN_OBSERVER: 1n << 16n,
    CAN_TRANSFER: 1n << 20n, // admin only?
    BURN: 1n << 24n,
    UPGRADE: 1n << 28n,
  },
  // see: L2/ETHRegistrar.sol
  ETH_REGISTRAR: {
    SET_ORACLE: 1n << 0n,
  },
  // see: LibBridgeRoles.sol
  BRIDGE: {
    EJECTOR: 1n << 0n,
  },
} as const satisfies Flags;

function mapFlags<T extends Flags>(flags: T, fn: (x: bigint) => bigint): T {
  return Object.fromEntries(
    Object.entries(flags).map(([k, x]) => [
      k,
      typeof x === "bigint" ? fn(x) : mapFlags(x, fn),
    ]),
  ) as T;
}

function adminify(x: bigint) {
  return x << 128n;
}

const ADMIN = mapFlags(OWNER, adminify);
const BOTH = mapFlags(OWNER, (x) => adminify(x) | x);

const ALL = 0x1111111111111111111111111111111111111111111111111111111111111111n; // see: EnhancedAccessControl.sol
//const ALL_ADMIN = adminify(ALL);

export const ROLES = {
  OWNER,
  ADMIN,
  BOTH,

  ALL,

  // see ETHRegistry.sol
  ETH_REGISTRY:
    ADMIN.REGISTRY.CAN_TRANSFER |
    BOTH.REGISTRY.SET_SUBREGISTRY |
    BOTH.REGISTRY.SET_RESOLVER |
    BOTH.REGISTRY.SET_TOKEN_OBSERVER,
} as const;
