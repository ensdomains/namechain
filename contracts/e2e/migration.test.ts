import { describe, it, beforeAll, beforeEach, afterAll } from "bun:test";
import {
  type Address,
  encodeAbiParameters,
  getAddress,
  labelhash,
  namehash,
  zeroAddress,
} from "viem";

import {
  type CrossChainEnvironment,
  type CrosschainSnapshot,
  setupCrossChainEnvironment,
} from "../script/setup.js";
import { type MockRelay, setupMockRelay } from "../script/mockRelay.js";
import { dnsEncodeName } from "../test/utils/utils.js";
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

describe("Migration", () => {
  let env: CrossChainEnvironment;
  let relay: MockRelay;
  let resetState: CrosschainSnapshot;
  beforeAll(async () => {
    env = await setupCrossChainEnvironment();
    relay = setupMockRelay(env);
    const { owner } = env.namedAccounts;
    await env.l1.contracts.ETHRegistrarV1.write.addController([owner.address], {
      account: owner,
    });
    resetState = await env.saveState();
  });
  afterAll(() => env?.shutdown());
  beforeEach(() => resetState?.());

  async function registerUnwrappedV1(
    label: string,
    owner: Address,
    duration = 86400n,
  ) {
    // const commitment = await env.l1.contracts.ethRegistrarControllerV1.read.makeCommitment([]);
    // await env.l1.contracts.ethRegistrarControllerV1.write.commit();
    const tokenId = BigInt(labelhash(label));
    await env.l1.contracts.ETHRegistrarV1.write.register(
      [tokenId, owner, duration],
      { account: env.namedAccounts.owner },
    );
    return tokenId;
  }

  const testLabel = "test";
  const testName = `${testLabel}.eth`;
  const subregistry = "0x1111111111111111111111111111111111111111";
  const resolver = "0x2222222222222222222222222222222222222222";

  describe("Migration", () => {
    describe("Unlocked", () => {
      it("unwrapped 2LD => L1", async () => {
        const { user } = env.namedAccounts;
        const tokenIdV1 = await registerUnwrappedV1(testLabel, user.address);
        const expires = await env.l1.contracts.ETHRegistrarV1.read.nameExpires([
          tokenIdV1,
        ]);
        await env.l1.contracts.ETHRegistrarV1.write.safeTransferFrom(
          [
            user.address,
            env.l1.contracts.UnlockedMigrationController.address,
            tokenIdV1,
            encodeAbiParameters(migrationDataAbi, [
              {
                transferData: {
                  dnsEncodedName: dnsEncodeName(testName),
                  owner: user.address,
                  subregistry,
                  resolver,
                  roleBitmap: 0n,
                  expires,
                },
                toL1: true,
                salt: 0n,
              },
            ]),
          ],
          { account: user },
        );
        const [, entry] = await env.l1.contracts.ETHRegistry.read.getNameData([
          testLabel,
        ]);
        expectVar({ entry }).toMatchObject({
          expiry: expires,
          subregistry,
          resolver,
        });
      });

      it("unwrapped 2LD => L2", async () => {
        const { user } = env.namedAccounts;
        const tokenIdV1 = await registerUnwrappedV1(testLabel, user.address);
        const expires = await env.l1.contracts.ETHRegistrarV1.read.nameExpires([
          tokenIdV1,
        ]);
        await env.l2.contracts.ETHRegistry.write.register([
          testLabel,
          env.l2.contracts.BridgeController.address,
          zeroAddress,
          zeroAddress,
          ROLES.ADMIN.EAC.CAN_TRANSFER,
          expires,
        ]);
        await relay.waitFor(
          env.l1.contracts.ETHRegistrarV1.write.safeTransferFrom(
            [
              user.address,
              env.l1.contracts.UnlockedMigrationController.address,
              tokenIdV1,
              encodeAbiParameters(migrationDataAbi, [
                {
                  transferData: {
                    dnsEncodedName: dnsEncodeName(testName),
                    owner: user.address,
                    subregistry,
                    resolver,
                    roleBitmap: 0n,
                    expires,
                  },
                  toL1: false,
                  salt: 0n,
                },
              ]),
            ],
            { account: user },
          ),
        );
        const [, entry] = await env.l2.contracts.ETHRegistry.read.getNameData([
          testLabel,
        ]);
        expectVar({ entry }).toMatchObject({
          expiry: expires,
          subregistry,
          resolver,
        });
      });

      it("wrapped 2LD => L1", async () => {
        const { user } = env.namedAccounts;
        const tokenIdV1 = await registerUnwrappedV1(testLabel, user.address);
        const expires = await env.l1.contracts.ETHRegistrarV1.read.nameExpires([
          tokenIdV1,
        ]);
        await env.l1.contracts.ETHRegistrarV1.write.approve(
          [env.l1.contracts.NameWrapperV1.address, tokenIdV1],
          { account: user },
        );
        await env.l1.contracts.NameWrapperV1.write.wrapETH2LD(
          [testLabel, user.address, 0, zeroAddress],
          { account: user },
        );
        await env.l1.contracts.NameWrapperV1.write.safeTransferFrom(
          [
            user.address,
            env.l1.contracts.UnlockedMigrationController.address,
            BigInt(namehash(testName)),
            1n,
            encodeAbiParameters(migrationDataAbi, [
              {
                transferData: {
                  dnsEncodedName: dnsEncodeName(testName),
                  owner: user.address,
                  subregistry,
                  resolver,
                  roleBitmap: 0n,
                  expires,
                },
                toL1: true,
                salt: 0n,
              },
            ]),
          ],
          { account: user },
        );
        const [, entry] = await env.l1.contracts.ETHRegistry.read.getNameData([
          testLabel,
        ]);
        expectVar({ entry }).toMatchObject({
          expiry: expires,
          subregistry,
          resolver,
        });
      });
    });
  });

  describe("Ejection", () => {
    it("2LD => L1", async () => {
      const { user } = env.namedAccounts;
      const expires = BigInt(Math.floor(Date.now() / 1000) + 86400);
      await env.l2.contracts.ETHRegistry.write.register([
        testLabel,
        user.address,
        subregistry,
        resolver,
        ROLES.ETH_REGISTRY,
        expires,
      ]);
      const [tokenId0] = await env.l2.contracts.ETHRegistry.read.getNameData([
        testLabel,
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
                dnsEncodedName: dnsEncodeName(`${testLabel}.eth`),
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
        await env.l1.contracts.ETHRegistry.read.getNameData([testLabel]);
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
