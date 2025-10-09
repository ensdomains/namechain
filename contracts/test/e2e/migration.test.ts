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
} from "viem";
import { AbiParametersToPrimitiveTypes } from "abitype";

import {
  type CrossChainEnvironment,
  type CrossChainSnapshot,
  setupCrossChainEnvironment,
} from "../../script/setup.js";
import { type MockRelay, setupMockRelay } from "../../script/mockRelay.js";
import { dnsEncodeName, labelToCanonicalId } from "../../test/utils/utils.js";
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

// see: LockedMigrationController.sol
const lockedMigrationDataAbi = [
  {
    type: "tuple",
    components: [
      { name: "node", type: "bytes32" },
      { name: "owner", type: "address" },
      { name: "resolver", type: "address" },
      { name: "salt", type: "uint256" },
    ],
  },
] as const;

// see: TransferData.sol
const transferDataAbi = [
  {
    type: "tuple",
    components: [
      { name: "label", type: "string" },
      { name: "owner", type: "address" },
      { name: "subregistry", type: "address" },
      { name: "resolver", type: "address" },
      { name: "roleBitmap", type: "uint256" },
      { name: "expiry", type: "uint64" },
    ],
  },
] as const;

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
  beforeAll(async () => {
    env = await setupCrossChainEnvironment();
    relay = setupMockRelay(env);
    // add owner as controller so we can register() directly
    const { owner } = env.namedAccounts;
    await env.l1.contracts.ETHRegistrarV1.write.addController([owner.address], {
      account: owner,
    });
    resetState = await env.saveState();
    //env.l1.logAnvil();
    //env.l2.logAnvil();
  });

  afterAll(() => env?.shutdown());
  beforeEach(() => resetState?.());

  const subregistry = "0x1111111111111111111111111111111111111111";
  const resolver = "0x2222222222222222222222222222222222222222";

  const defaultUnlockedData = {
    resolver,
    subregistry,
    roleBitmap: 0n,
    salt: 0n,
  } as const;

  class Wrapped {
    constructor(
      readonly name: string,
      readonly account: Account,
    ) {}
    get namehash() {
      return namehash(this.name);
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
      return new Wrapped(dnsEncodeName(`${label}.${this.name}`), owner);
    }
    //unwrappedTransferData(toL1: boolean) {}
  }

  async function registerV1({
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
      return new Wrapped(name, account);
    }
  }

  describe("Migration", () => {
    describe("Unlocked", () => {
      it("unwrapped 2LD => L1", async () => {
        const { label, account, expiry, approve } = await registerV1();
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
          subregistry,
          resolver,
        });
      });

      it("unwrapped 2LD => L2", async () => {
        const { label, account, expiry, approve } = await registerV1();
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
          subregistry,
          resolver,
        });
      });

      it("wrapped 2LD => L1", async () => {
        const { label, account, expiry, wrap } = await registerV1();
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
          subregistry,
          resolver,
        });
      });

      function migrate(unwrapped: number, wrapped: number) {
        it(`${unwrapped}u + ${wrapped}w`, async () => {
          const items: { td: UnlockedMigrationData; expiry: bigint }[] = [];
          const account = env.namedAccounts.user;
          for (let i = 0; i < unwrapped; i++) {
            const { label, expiry } = await registerV1({
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
            const { label, expiry, wrap } = await registerV1({
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
          const { label, account, wrap } = await registerV1();
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
          const { label, account } = await registerV1({
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
          const { label, account, wrap } = await registerV1({
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
          const { label, account, approve } = await registerV1();
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

    // describe("Locked", () => {
    //   it("locked", async () => {
    //     const { account, wrap } = await registerV1();
    //     const wrapped = await wrap(FUSES.CANNOT_UNWRAP);
    //     await wrapped.approve();

    //     // await env.l1.contracts.NameWrapperV1.write.safeTransferFrom(
    //     //   [
    //     //     account.address,
    //     //     env.l1.contracts.LockedMigrationController.address,
    //     //     await wrap(FUSES.CANNOT_UNWRAP),
    //     //     1n,
    //     //     transferData(false),
    //     //   ],
    //     //   { account },
    //     // );
    //   });
    // });
  });

  // TODO: finish this after migration tests
  describe("Ejection", () => {
    it("2LD => L1", async () => {
      const account = env.namedAccounts.user2;
      const label = "testabss2";
      const expiry = BigInt(Math.floor(Date.now() / 1000) + 86400);
      await env.l2.contracts.ETHRegistry.write.register([
        label,
        account.address,
        subregistry,
        resolver,
        ROLES.ETH_REGISTRY,
        expiry,
      ]);
      const [tokenId0] = await env.l2.contracts.ETHRegistry.read.getNameData([
        label,
      ]);
      await relay.waitFor(
        env.l2.contracts.ETHRegistry.write.safeTransferFrom(
          [
            account.address,
            env.l2.contracts.BridgeController.address,
            tokenId0,
            1n,
            encodeAbiParameters(transferDataAbi, [
              {
                label,
                owner: account.address,
                subregistry,
                resolver,
                roleBitmap: ROLES.ETH_REGISTRY,
                expiry,
              },
            ]),
          ],
          { account },
        ),
      );

      // await relay.waitFor(
      //   env.l2.contracts.ETHRegistry.write.safeTransferFrom(
      //     [
      //       user.address,
      //       env.l2.contracts.BridgeController.address,
      //       tokenId0,
      //       1n,
      //       encodeAbiParameters(transferDataAbi, [
      //         {
      //           label,
      //           owner: user.address,
      //           subregistry,
      //           resolver,
      //           roleBitmap: ROLES.ETH_REGISTRY,
      //           expiry,
      //         },
      //       ]),
      //     ],
      //     { account: user },
      //   ),
      // );
      // const [tokenId1, entry] =
      //   await env.l1.contracts.ETHRegistry.read.getNameData([label]);
      // expectVar({ entry }).toMatchObject({
      //   expiry,
      //   subregistry,
      //   resolver,
      // });
      // const owner0 = await env.l2.contracts.ETHRegistry.read.ownerOf([
      //   tokenId0,
      // ]);
      // expectVar({ owner0 }).toStrictEqual(
      //   getAddress(env.l2.contracts.BridgeController.address),
      // );
      // const owner1 = await env.l1.contracts.ETHRegistry.read.ownerOf([
      //   tokenId1,
      // ]);
      // expectVar({ owner1 }).toStrictEqual(user.address);
    });
  });
});
