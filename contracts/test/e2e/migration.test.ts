import {
  describe,
  it,
  beforeAll,
  beforeEach,
  afterAll,
  expect,
} from "bun:test";
import {
  Account,
  type Address,
  encodeAbiParameters,
  getAddress,
  labelhash,
  namehash,
  toHex,
  zeroAddress,
  BaseError,
  ContractFunctionRevertedError,
  ContractFunctionExecutionError,
  Hex,
  decodeAbiParameters,
  stringToHex,
  decodeErrorResult,
  slice,
  keccak256,
} from "viem";
import {
  Abi,
  AbiParameter,
  AbiParametersToPrimitiveTypes,
  AbiParameterToPrimitiveType,
} from "abitype";

import {
  type CrossChainEnvironment,
  type CrossChainSnapshot,
  setupCrossChainEnvironment,
} from "../../script/setup.js";
import { type MockRelay, setupMockRelay } from "../../script/mockRelay.js";
import {
  dnsEncodeName,
  getLabelAt,
  labelToCanonicalId,
} from "../../test/utils/utils.js";
import { expectVar } from "../utils/expectVar.js";
import { ROLES, MAX_EXPIRY } from "../../deploy/constants.js";

// see: UnlockedMigrationController.sol
const unlockedMigrationDataAbi = [
  {
    type: "tuple",
    components: [
      { name: "toL1", type: "bool" },
      { name: "label", type: "string" },
      { name: "owner", type: "address" },
      { name: "resolver", type: "address" },
      { name: "subregistry", type: "address" },
      { name: "roleBitmap", type: "uint256" },
      { name: "salt", type: "uint256" },
    ],
  },
] as const;

const lockedMigrationDataComponents = [
  { name: "node", type: "bytes32" },
  { name: "owner", type: "address" },
  { name: "resolver", type: "address" },
  { name: "salt", type: "uint256" },
] as const satisfies AbiParameter[];

// see: LockedMigrationController.sol
const lockedMigrationDataAbi = {
  type: "tuple",
  components: [
    { name: "node", type: "bytes32" },
    { name: "owner", type: "address" },
    { name: "resolver", type: "address" },
    { name: "salt", type: "uint256" },
  ],
} as const;
type LockedMigrationData = AbiParameterToPrimitiveType<
  typeof lockedMigrationDataAbi
>;

type UnlockedMigrationData = AbiParametersToPrimitiveTypes<
  typeof unlockedMigrationDataAbi
>[0];
// type LockedMigrationData = AbiParametersToPrimitiveTypes<
//   typeof lockedMigrationDataAbi
// >[0];
// type TransferData = AbiParametersToPrimitiveTypes<typeof transferDataAbi>[0];

// see: INameWrapper.sol
const FUSES = {
  CANNOT_UNWRAP: 1 << 0,
  CANNOT_BURN_FUSES: 1 << 1,
  CANNOT_TRANSFER: 1 << 2,
  CANNOT_SET_RESOLVER: 1 << 3,
  CANNOT_SET_TTL: 1 << 4,
  CANNOT_CREATE_SUBDOMAIN: 1 << 5,
  CANNOT_APPROVE: 1 << 6,
  PARENT_CANNOT_CONTROL: 1 << 16,
  IS_DOT_ETH: 1 << 17,
  CAN_EXTEND_EXPIRY: 1 << 18,
  CAN_DO_EVERYTHING: 0,
} as const;

const FUSE_MASKS = {
  PARENT_CONTROLLED: 0xffff0000,
  PARENT_RESERVED: 0x0000ff80, // bits 7-15 (docs say 17-32)
  USER_SETTABLE: 0xfffdffff, // ~IS_DOT_ETH
} as const;

function fuseName(fuses: number) {
  return Object.entries(fuses)
    .reduce<string[]>((a, [key, bit]) => {
      if (fuses & bit) a.push(key);
      return a;
    }, [])
    .join(" + ");
}

// https://www.notion.so/enslabs/ENS-v2-Design-Doc-291bb4ab8b26440fbbac46d1aaba1b83
// https://www.notion.so/enslabs/ENSv2-Migration-Plan-23b7a8b1f0ed80ee832df953abc80810

describe("Migration", () => {
  let env: CrossChainEnvironment;
  let relay: MockRelay;
  let resetState: CrossChainSnapshot;
  let nextSalt = 0n;
  beforeAll(async () => {
    env = await setupCrossChainEnvironment({ procLog: true }); // show anvil logs
    relay = setupMockRelay(env);

    // add owner as controller so we can register() directly
    const { owner } = env.namedAccounts;
    await env.l1.contracts.ETHRegistrarV1.write.addController([owner.address], {
      account: owner,
    });

    resetState = await env.saveState();
  });

  afterAll(() => env?.shutdown());
  beforeEach(() => resetState?.());

  function unwrapError(err: unknown): never {
    if (err instanceof ContractFunctionExecutionError) {
      if (err.cause instanceof ContractFunctionRevertedError) {
        let { raw } = err.cause;
        if (raw?.startsWith("0x08c379a0")) {
          [raw] = decodeAbiParameters([{ type: "bytes" }], slice(raw, 4));
          if (raw.startsWith(stringToHex("❌("))) {
            const abi = [
              ...env.l1.contracts.UnlockedMigrationController.abi,
              ...env.l1.contracts.LockedMigrationController.abi,
              ...env.l1.contracts.MigratedWrappedNameRegistryImpl.abi,
              ...env.interfaces.CommonErrors,
              ...env.interfaces.TransferErrors,
            ];
            const newErr = new ContractFunctionRevertedError({
              abi,
              data: slice(raw, 4),
              functionName: err.functionName,
            });
            if (newErr.data) {
              throw new ContractFunctionExecutionError(newErr, err);
            }
          }
        }
      }
    }
    throw err;
  }

  const SUBREGISTRY = "0x1111111111111111111111111111111111111111";
  const RESOLVER = "0x2222222222222222222222222222222222222222";

  const defaultUnlockedData = {
    resolver: RESOLVER,
    subregistry: SUBREGISTRY,
    roleBitmap: 0n,
    salt: 0n,
  } as const;

  class WrappedToken {
    constructor(
      readonly name: string,
      readonly account: Account,
    ) {}
    get namehash() {
      return namehash(this.name);
    }
    get tokenId() {
      return BigInt(this.namehash);
    }
    label(i = 0) {
      return getLabelAt(this.name, i);
    }
    async approve() {
      return env.l1.contracts.NameWrapperV1.write.setApprovalForAll(
        [env.l1.contracts.UnlockedMigrationController.address, true],
        { account: this.account },
      );
    }
    async createChild({
      label = "sub",
      fuses = 0,
      owner = this.account,
    }: {
      label?: string;
      fuses?: number;
      owner?: Account;
    } = {}) {
      await env.l1.contracts.NameWrapperV1.write.setSubnodeOwner(
        [this.namehash, label, owner.address, fuses, MAX_EXPIRY],
        { account: this.account },
      );
      return new WrappedToken(`${label}.${this.name}`, owner);
    }
    lockedTransferTuple({
      owner = this.account.address,
      resolver = RESOLVER,
      salt = this.tokenId ^ ++nextSalt,
    }: Partial<Omit<LockedMigrationData, "node">> = {}) {
      return { node: this.namehash, owner, resolver, salt };
    }
  }

  function encodeLockedMigrationData(
    v: LockedMigrationData | LockedMigrationData[],
  ) {
    if (Array.isArray(v)) {
      return encodeAbiParameters(
        [{ type: "tuple[]", components: lockedMigrationDataComponents }],
        [v],
      );
    } else {
      return encodeAbiParameters(
        [{ type: "tuple", components: lockedMigrationDataComponents }],
        [v],
      );
    }
  }

  async function registerUnwrapped({
    label = "test",
    account = env.namedAccounts.user,
    duration = 86400n,
  }: {
    label?: string;
    account?: Account;
    duration?: bigint;
  } = {}) {
    //const commitment = await env.l1.contracts.ethRegistrarControllerV1.read.makeCommitment([]);
    //await env.l1.contracts.ethRegistrarControllerV1.write.commit();
    const unwrappedTokenId = BigInt(labelhash(label));
    // register using controller hack
    await env.l1.contracts.ETHRegistrarV1.write.register(
      [unwrappedTokenId, account.address, duration],
      { account: env.namedAccounts.owner },
    );
    const expiry = await env.l1.contracts.ETHRegistrarV1.read.nameExpires([
      unwrappedTokenId,
    ]);
    // ensure V1 has ejected token
    await env.l2.contracts.ETHRegistry.write.register([
      label,
      env.l2.contracts.BridgeController.address,
      zeroAddress,
      zeroAddress,
      ROLES.ADMIN.REGISTRY.CAN_TRANSFER,
      expiry,
    ]);
    await env.l2.contracts.ETHRegistry.write.setTokenObserver([
      labelToCanonicalId(label),
      env.l2.contracts.BridgeController.address,
    ]);
    const name = `${label}.eth`;
    return {
      label,
      name,
      account,
      unwrappedTokenId,
      expiry,
      approve,
      wrap,
    };
    async function approve() {
      await env.l1.contracts.ETHRegistrarV1.write.setApprovalForAll(
        [env.l1.contracts.UnlockedMigrationController.address, true],
        { account },
      );
    }
    async function wrap(fuses: number = FUSES.CAN_DO_EVERYTHING) {
      // i think this is simpler than doing it via transfer
      // TODO: check that this is equivalent to transfer
      await env.l1.contracts.ETHRegistrarV1.write.approve(
        [env.l1.contracts.NameWrapperV1.address, unwrappedTokenId],
        { account },
      );
      await env.l1.contracts.NameWrapperV1.write.wrapETH2LD(
        [label, account.address, fuses, zeroAddress],
        { account },
      );
      return new WrappedToken(name, account);
    }
  }

  async function registerWrapped(
    opts: {
      label?: string;
      account?: Account;
      duration?: bigint;
      fuses?: number;
    } = {},
  ) {
    const { wrap } = await registerUnwrapped(opts);
    return wrap(opts.fuses);
  }

  describe("Unlocked", () => {
    it("unwrapped 2LD => L1", async () => {
      const { label, account, expiry, approve } = await registerUnwrapped();
      await approve();
      await env.l1.contracts.UnlockedMigrationController.write.migrate(
        [
          {
            toL1: true,
            label,
            owner: account.address,
            ...defaultUnlockedData,
          },
        ],
        { account },
      );
      const [, entry] = await env.l1.contracts.ETHRegistry.read.getNameData([
        label,
      ]);
      expectVar({ entry }).toMatchObject({
        expiry,
        subregistry: SUBREGISTRY,
        resolver: RESOLVER,
      });
    });

    it("unwrapped 2LD => L2", async () => {
      const { label, account, expiry, approve } = await registerUnwrapped();
      await approve();
      await relay.waitFor(
        env.l1.contracts.UnlockedMigrationController.write.migrate(
          [
            {
              toL1: false,
              label,
              owner: account.address,
              ...defaultUnlockedData,
            },
          ],
          { account },
        ),
      );
      const [, entry] = await env.l2.contracts.ETHRegistry.read.getNameData([
        label,
      ]);
      expectVar({ entry }).toMatchObject({
        expiry,
        subregistry: SUBREGISTRY,
        resolver: RESOLVER,
      });
    });

    it("wrapped 2LD => L1", async () => {
      const { label, account, expiry, wrap } = await registerUnwrapped();
      const wrapped = await wrap();
      await wrapped.approve();
      await env.l1.contracts.UnlockedMigrationController.write.migrate(
        [
          {
            toL1: true,
            label,
            owner: account.address,
            ...defaultUnlockedData,
          },
        ],
        { account },
      );
      const [, entry] = await env.l1.contracts.ETHRegistry.read.getNameData([
        label,
      ]);
      expectVar({ entry }).toMatchObject({
        expiry,
        subregistry: SUBREGISTRY,
        resolver: RESOLVER,
      });
    });

    function migrate(unwrapped: number, wrapped: number) {
      it(`${unwrapped}u + ${wrapped}w`, async () => {
        const items: { td: UnlockedMigrationData; expiry: bigint }[] = [];
        const account = env.namedAccounts.user;
        for (let i = 0; i < unwrapped; i++) {
          const { label, expiry } = await registerUnwrapped({
            label: `u${i}`,
            account,
          });
          items.push({
            td: {
              toL1: true,
              label,
              owner: account.address,
              ...defaultUnlockedData,
            },
            expiry,
          });
        }
        for (let i = 0; i < wrapped; i++) {
          const { label, expiry, wrap } = await registerUnwrapped({
            label: `w${i}`,
            account,
          });
          await wrap();
          items.push({
            td: {
              toL1: true,
              label,
              owner: account.address,
              ...defaultUnlockedData,
            },
            expiry,
          });
        }
        if (unwrapped) {
          await env.l1.contracts.ETHRegistrarV1.write.setApprovalForAll(
            [env.l1.contracts.UnlockedMigrationController.address, true],
            { account },
          );
        }
        if (wrapped) {
          await env.l1.contracts.NameWrapperV1.write.setApprovalForAll(
            [env.l1.contracts.UnlockedMigrationController.address, true],
            { account },
          );
        }
        await env.l1.contracts.UnlockedMigrationController.write.migrate(
          [items.map((x) => x.td)],
          { account },
        );
      });
    }

    migrate(0, 1);
    migrate(1, 0);

    migrate(0, 2);
    migrate(1, 1);
    migrate(2, 1);

    describe("errors", () => {
      it(`locked 2LD fails`, async () => {
        const { label, account, wrap } = await registerUnwrapped();
        await wrap(FUSES.CANNOT_UNWRAP);
        await env.l1.contracts.NameWrapperV1.write.setApprovalForAll(
          [env.l1.contracts.UnlockedMigrationController.address, true],
          { account },
        );
        expect(
          env.l1.contracts.UnlockedMigrationController.write.migrate(
            [
              {
                toL1: true,
                label,
                owner: account.address,
                ...defaultUnlockedData,
              },
            ],
            { account },
          ),
        ).rejects.toThrow("NameIsLocked");
      });

      it("nonexistent token fails", async () => {
        const account = env.namedAccounts.user;
        expect(
          env.l1.contracts.UnlockedMigrationController.write.migrate(
            [
              {
                toL1: true,
                label: "abc",
                owner: account.address,
                ...defaultUnlockedData,
              },
            ],
            { account },
          ),
        ).rejects.toThrow(); // empty revert from ownerOf()
      });

      it("unowned unwrapped fails", async () => {
        const { label, account } = await registerUnwrapped({
          account: env.namedAccounts.user2,
        });
        expect(
          env.l1.contracts.UnlockedMigrationController.write.migrate(
            [
              {
                toL1: true,
                label,
                owner: account.address,
                ...defaultUnlockedData,
              },
            ],
            { account },
          ),
        ).rejects.toThrow("ERC721: caller is not token owner or approved");
      });

      it("unowned wrapped fails", async () => {
        const { label, account, wrap } = await registerUnwrapped({
          account: env.namedAccounts.user2,
        });
        await wrap();
        expect(
          env.l1.contracts.UnlockedMigrationController.write.migrate(
            [
              {
                toL1: true,
                label,
                owner: account.address,
                ...defaultUnlockedData,
              },
            ],
            { account },
          ),
        ).rejects.toThrow("ERC1155: caller is not owner nor approved");
      });

      // it("wrapped 3LD fails", async () => {
      //   const { account, wrap } = await registerV1();
      //   const parent = await wrap();
      //   const child = await parent.createChild();
      //   await env.l1.contracts.NameWrapperV1.write.setApprovalForAll(
      //     [env.l1.contracts.UnlockedMigrationController.address, true],
      //     { account },
      //   );
      // });

      it("invalid receipient", async () => {
        const { label, account, approve } = await registerUnwrapped();
        await approve();
        const { rxReceipts } = await relay.waitFor(
          env.l1.contracts.UnlockedMigrationController.write.migrate(
            [
              {
                toL1: false,
                label,
                owner: zeroAddress,
                ...defaultUnlockedData,
              },
            ],
            { account },
          ),
        );
        expect(rxReceipts).toHaveLength(1);
        expect(rxReceipts[0].status).toStrictEqual("error");
      });
    });
  });

  describe("Locked", () => {
    it("locked", async () => {
      const { account, wrap } = await registerUnwrapped();
      const token = await wrap(FUSES.CANNOT_UNWRAP);
      await env.l1.contracts.NameWrapperV1.write.safeTransferFrom(
        [
          account.address,
          env.l1.contracts.LockedMigrationController.address,
          token.tokenId,
          1n,
          encodeLockedMigrationData(token.lockedTransferTuple()),
        ],
        { account },
      );
    });

    it("locked x2", async () => {
      const account = env.namedAccounts.user;
      const fuses = FUSES.CANNOT_UNWRAP;
      const tokens = [
        await registerWrapped({ label: "test1", account, fuses }),
        await registerWrapped({ label: "test2", account, fuses }),
      ];
      await env.l1.contracts.NameWrapperV1.write.safeBatchTransferFrom(
        [
          account.address,
          env.l1.contracts.LockedMigrationController.address,
          tokens.map((x) => x.tokenId),
          tokens.map(() => 1n),
          encodeLockedMigrationData(tokens.map((x) => x.lockedTransferTuple())),
        ],
        { account },
      );
      for (const x of tokens) {
        const [tokenId, entry] =
          await env.l1.contracts.ETHRegistry.read.getNameData([x.label()]);
        const owner = await env.l1.contracts.ETHRegistry.read.ownerOf([
          tokenId,
        ]);
        const expiryV1 = await env.l1.contracts.ETHRegistrarV1.read.nameExpires(
          [BigInt(labelhash(x.label()))],
        );
        expect(owner, "owner").toStrictEqual(x.account.address);
        expect(entry.expiry, "expiry").toStrictEqual(expiryV1);
        expect(entry.resolver, "resolver").toStrictEqual(RESOLVER);
      }
    });

    describe("single errors", () => {
      it("invalid amount: 0", async () => {
        const token = await registerWrapped();
        expect(
          env.l1.contracts.NameWrapperV1.write.safeTransferFrom(
            [
              token.account.address,
              env.l1.contracts.LockedMigrationController.address,
              token.tokenId,
              0n, // wrong
              encodeLockedMigrationData([]),
            ],
            { account: token.account },
          ),
        ).rejects.toThrow("ERC1155: insufficient balance for transfer");
      });

      it("invalid amount: 2", async () => {
        const token = await registerWrapped();
        expect(
          env.l1.contracts.NameWrapperV1.write.safeTransferFrom(
            [
              token.account.address,
              env.l1.contracts.LockedMigrationController.address,
              token.tokenId,
              2n, // wrong
              encodeLockedMigrationData([]),
            ],
            { account: token.account },
          ),
        ).rejects.toThrow("ERC1155: insufficient balance for transfer");
      });

      it("invalid transfer data", async () => {
        const token = await registerWrapped();
        expect(
          env.l1.contracts.NameWrapperV1.write
            .safeTransferFrom(
              [
                token.account.address,
                env.l1.contracts.LockedMigrationController.address,
                token.tokenId,
                1n,
                "0x1234",
              ],
              { account: token.account },
            )
            .catch(unwrapError),
        ).rejects.toThrow("InvalidTransferData()");
      });

      it("invalid owner", async () => {
        const token = await registerWrapped();
        expect(
          env.l1.contracts.NameWrapperV1.write
            .safeTransferFrom(
              [
                token.account.address,
                env.l1.contracts.LockedMigrationController.address,
                token.tokenId,
                1n,
                encodeLockedMigrationData({
                  ...token.lockedTransferTuple(),
                  owner: zeroAddress, // wrong
                }),
              ],
              { account: token.account },
            )
            .catch(unwrapError),
        ).rejects.toThrow("InvalidOwner()");
      });

      it("token node mismatch", async () => {
        const token = await registerWrapped();
        expect(
          env.l1.contracts.NameWrapperV1.write
            .safeTransferFrom(
              [
                token.account.address,
                env.l1.contracts.LockedMigrationController.address,
                token.tokenId,
                1n,
                encodeLockedMigrationData({
                  ...token.lockedTransferTuple(),
                  node: "0x1111111111111111111111111111111111111111111111111111111111111111", // wrong
                }),
              ],
              { account: token.account },
            )
            .catch(unwrapError),
        ).rejects.toThrow("TokenNodeMismatch(");
      });

      it("not ETH2LD", async () => {
        const parentToken = await registerWrapped();
        const token = await parentToken.createChild();
        expect(
          env.l1.contracts.NameWrapperV1.write
            .safeTransferFrom(
              [
                token.account.address,
                env.l1.contracts.LockedMigrationController.address,
                token.tokenId,
                1n,
                encodeLockedMigrationData(token.lockedTransferTuple()),
              ],
              { account: token.account },
            )
            .catch(unwrapError),
        ).rejects.toThrow("NameNotETH2LD(");
      });
    });

    describe("batch errors", () => {
      it("invalid array length: ids & amounts", async () => {
        const account = env.namedAccounts.user;
        const fuses = FUSES.CANNOT_UNWRAP;
        const tokens = [await registerWrapped({ account, fuses })];
        expect(
          env.l1.contracts.NameWrapperV1.write.safeBatchTransferFrom(
            [
              account.address,
              env.l1.contracts.LockedMigrationController.address,
              tokens.map((x) => x.tokenId),
              [], // wrong
              encodeLockedMigrationData(
                tokens.map((x) => x.lockedTransferTuple()),
              ),
            ],
            { account },
          ),
        ).rejects.toThrow("ERC1155: ids and amounts length mismatch");
      });

      it("invalid array length: ids & data", async () => {
        const account = env.namedAccounts.user;
        const fuses = FUSES.CANNOT_UNWRAP;
        const tokens = [await registerWrapped({ account, fuses })];
        expect(
          env.l1.contracts.NameWrapperV1.write
            .safeBatchTransferFrom(
              [
                account.address,
                env.l1.contracts.LockedMigrationController.address,
                tokens.map((x) => x.tokenId),
                tokens.map(() => 1n),
                encodeLockedMigrationData([]), // wrong
              ],
              { account },
            )
            .catch(unwrapError),
        ).rejects.toThrow("ERC1155InvalidArrayLength(");
      });

      it("invalid transfer data", async () => {
        const account = env.namedAccounts.user;
        const fuses = FUSES.CANNOT_UNWRAP;
        const tokens = [await registerWrapped({ account, fuses })];
        expect(
          env.l1.contracts.NameWrapperV1.write
            .safeBatchTransferFrom(
              [
                account.address,
                env.l1.contracts.LockedMigrationController.address,
                tokens.map((x) => x.tokenId),
                tokens.map(() => 1n),
                "0x1234", // wrong
              ],
              { account },
            )
            .catch(unwrapError),
        ).rejects.toThrow("InvalidTransferData()");
      });
    });
  });
});
