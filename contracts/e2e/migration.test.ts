import {
  describe,
  it,
  beforeAll,
  beforeEach,
  afterAll,
  expect,
} from "bun:test";
import {
  type Address,
  encodeAbiParameters,
  getAddress,
  labelhash,
  namehash,
  toHex,
  zeroAddress,
} from "viem";

import {
  type CrossChainEnvironment,
  type CrosschainSnapshot,
  setupCrossChainEnvironment,
} from "../script/setup.js";
import { type MockRelay, setupMockRelay } from "../script/mockRelay.js";
import { dnsEncodeName, labelToCanonicalId } from "../test/utils/utils.js";
import { expectVar } from "../test/utils/expectVar.js";
import { ROLES } from "../deploy/constants.js";

const transferDataAbi = [
  {
    type: "tuple",
    components: [
      { name: "dnsEncodedName", type: "bytes" },
      { name: "owner", type: "address" },
      { name: "subregistry", type: "address" },
      { name: "resolver", type: "address" },
      { name: "roleBitmap", type: "uint256" },
      { name: "expires", type: "uint64" },
    ],
  },
] as const;

const migrationDataAbi = [
  {
    type: "tuple",
    components: [
      { name: "transferData", ...transferDataAbi[0] },
      { name: "toL1", type: "bool" },
      { name: "salt", type: "uint256" },
    ],
  },
] as const;

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
  let resetState: CrosschainSnapshot;
  beforeAll(async () => {
    env = await setupCrossChainEnvironment();
    relay = setupMockRelay(env);
    // add owner as controller
    const { owner } = env.namedAccounts;
    await env.l1.contracts.ETHRegistrarV1.write.addController([owner.address], {
      account: owner,
    });
    resetState = await env.saveState();
  });
  afterAll(() => env?.shutdown());
  beforeEach(() => resetState?.());

  const subregistry = "0x1111111111111111111111111111111111111111";
  const resolver = "0x2222222222222222222222222222222222222222";

  async function registerV1(
    label = "test",
    account = env.namedAccounts.user,
    duration = 86400n,
  ) {
    //const commitment = await env.l1.contracts.ethRegistrarControllerV1.read.makeCommitment([]);
    //await env.l1.contracts.ethRegistrarControllerV1.write.commit();
    const unwrappedTokenId = BigInt(labelhash(label));
    // register using controller hack
    await env.l1.contracts.ETHRegistrarV1.write.register(
      [unwrappedTokenId, account.address, duration],
      { account: env.namedAccounts.owner },
    );
    const expires = await env.l1.contracts.ETHRegistrarV1.read.nameExpires([
      unwrappedTokenId,
    ]);
    // ensure V1 has ejected token
    await env.l2.contracts.ETHRegistry.write.register([
      label,
      env.l2.contracts.BridgeController.address,
      zeroAddress,
      zeroAddress,
      ROLES.ADMIN.EAC.CAN_TRANSFER,
      expires,
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
      expires,
      wrap,
      transferData,
    };
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
      return BigInt(namehash(name)); // wrappedTokenId
    }
    function transferData(namechain: boolean, roleBitmap = 0n, salt = 0n) {
      return encodeAbiParameters(migrationDataAbi, [
        {
          transferData: {
            dnsEncodedName: dnsEncodeName(name),
            owner: account.address,
            subregistry,
            resolver,
            roleBitmap,
            expires,
          },
          toL1: !namechain,
          salt,
        },
      ]);
    }
  }

  describe("Migration", () => {
    describe("Unlocked", () => {
      it("unwrapped 2LD => L1", async () => {
        const { label, account, unwrappedTokenId, expires, transferData } =
          await registerV1();
        await env.l1.contracts.ETHRegistrarV1.write.safeTransferFrom(
          [
            account.address,
            env.l1.contracts.UnlockedMigrationController.address,
            unwrappedTokenId,
            transferData(false),
          ],
          { account },
        );
        const [, entry] = await env.l1.contracts.ETHRegistry.read.getNameData([
          label,
        ]);
        expectVar({ entry }).toMatchObject({
          expiry: expires,
          subregistry,
          resolver,
        });
      });

      it("unwrapped 2LD => L2", async () => {
        const { label, account, unwrappedTokenId, expires, transferData } =
          await registerV1();
        await relay.waitFor(
          env.l1.contracts.ETHRegistrarV1.write.safeTransferFrom(
            [
              account.address,
              env.l1.contracts.UnlockedMigrationController.address,
              unwrappedTokenId,
              transferData(true),
            ],
            { account },
          ),
        );
        const [, entry] = await env.l2.contracts.ETHRegistry.read.getNameData([
          label,
        ]);
        expectVar({ entry }).toMatchObject({
          expiry: expires,
          subregistry,
          resolver,
        });
      });

      it("wrapped 2LD => L1", async () => {
        const { label, account, expires, wrap, transferData } =
          await registerV1();
        await env.l1.contracts.NameWrapperV1.write.safeTransferFrom(
          [
            account.address,
            env.l1.contracts.UnlockedMigrationController.address,
            await wrap(),
            1n,
            transferData(false),
          ],
          { account },
        );
        const [, entry] = await env.l1.contracts.ETHRegistry.read.getNameData([
          label,
        ]);
        expectVar({ entry }).toMatchObject({
          expiry: expires,
          subregistry,
          resolver,
        });
      });

      function tryWithFuse(fuses: number, error: string) {
        it(`wrapped w/${fuseName(fuses)} fails`, async () => {
          const { account, wrap, transferData } = await registerV1();
          expect(
            env.l1.contracts.NameWrapperV1.write.safeTransferFrom(
              [
                account.address,
                env.l1.contracts.UnlockedMigrationController.address,
                await wrap(fuses),
                1n,
                transferData(false),
              ],
              { account },
            ),
          ).rejects.toThrow(error);
        });
      }

      tryWithFuse(
        FUSES.CANNOT_UNWRAP,
        "ERC1155: transfer to non ERC1155Receiver implementer",
      );
      tryWithFuse(
        FUSES.CANNOT_UNWRAP | FUSES.CANNOT_TRANSFER,
        "OperationProhibited",
      );
    });

    describe("Locked", () => {
      it("locked => L1", async () => {
        const {account, wrap, transferData} = await registerV1();
        await env.l1.contracts.NameWrapperV1.write.safeTransferFrom(
          [
            account.address,
            env.l1.contracts.LockedMigrationController.address,
            await wrap(FUSES.CANNOT_UNWRAP),
            1n,
            transferData(false),
          ],
          { account },
        );



      });
    });
  });

  // TODO: finish this after migration tests
  describe("Ejection", () => {
    it("2LD => L1", async () => {
      const { user } = env.namedAccounts;
      const testLabel2LD = "test";
      const expires = BigInt(Math.floor(Date.now() / 1000) + 86400);
      await env.l2.contracts.ETHRegistry.write.register([
        testLabel2LD,
        user.address,
        subregistry,
        resolver,
        ROLES.ETH_REGISTRY,
        expires,
      ]);
      const [tokenId0] = await env.l2.contracts.ETHRegistry.read.getNameData([
        testLabel2LD,
      ]);
      await relay.waitFor(
        env.l2.contracts.ETHRegistry.write.safeTransferFrom(
          [
            user.address,
            env.l2.contracts.BridgeController.address,
            tokenId0,
            1n,
            encodeAbiParameters(transferDataAbi, [
              {
                dnsEncodedName: dnsEncodeName(`${testLabel2LD}.eth`),
                owner: user.address,
                subregistry,
                resolver,
                roleBitmap: ROLES.ETH_REGISTRY,
                expires,
              },
            ]),
          ],
          { account: user },
        ),
      );
      const [tokenId1, entry] =
        await env.l1.contracts.ETHRegistry.read.getNameData([testLabel2LD]);
      expectVar({ entry }).toMatchObject({
        expiry: expires,
        subregistry,
        resolver,
      });
      const owner0 = await env.l2.contracts.ETHRegistry.read.ownerOf([
        tokenId0,
      ]);
      expectVar({ owner0 }).toStrictEqual(
        getAddress(env.l2.contracts.BridgeController.address),
      );
      const owner1 = await env.l1.contracts.ETHRegistry.read.ownerOf([
        tokenId1,
      ]);
      expectVar({ owner1 }).toStrictEqual(user.address);
    });
  });
});
