import { afterAll, beforeAll, beforeEach, describe, it } from "bun:test";
import { Account, encodeAbiParameters, labelhash, zeroAddress } from "viem";

import { ROLES } from "../../deploy/constants.js";
import { type CrossChainSnapshot } from "../../script/setup.js";
import { dnsEncodeName, labelToCanonicalId } from "../../test/utils/utils.js";
import { expectVar } from "../utils/expectVar.js";

// see: TransferData.sol
const migrationDataAbi = [
  {
    type: "tuple",
    components: [
      {
        name: "transferData",
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
      { name: "toL1", type: "bool" },
      { name: "salt", type: "uint256" },
    ],
  },
] as const;

// https://www.notion.so/enslabs/ENS-v2-Design-Doc-291bb4ab8b26440fbbac46d1aaba1b83
// https://www.notion.so/enslabs/ENSv2-Migration-Plan-23b7a8b1f0ed80ee832df953abc80810

describe("Migration", () => {
  const { env, relay, setupEnv } = process.env.TEST_GLOBALS!;

  setupEnv(async () => {
    // add owner as controller so we can register() directly
    const { owner } = env.namedAccounts;
    await env.l1.contracts.ETHRegistrarV1.write.addController([owner.address], {
      account: owner,
    });
  });

  const SUBREGISTRY = "0x1111111111111111111111111111111111111111";
  const RESOLVER = "0x2222222222222222222222222222222222222222";

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
      ROLES.ALL,
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
    };
  }

  describe("Unlocked", () => {
    it("unwrapped 2LD => L2", async () => {
      const { label, account, expiry } = await registerUnwrapped();
      await relay.waitFor(
        env.l1.contracts.ETHRegistrarV1.write.safeTransferFrom(
          [
            account.address,
            env.l1.contracts.UnlockedMigrationController.address,
            BigInt(labelhash(label)),
            encodeAbiParameters(migrationDataAbi, [
              {
                transferData: {
                  dnsEncodedName: dnsEncodeName(`${label}.eth`),
                  owner: account.address,
                  subregistry: SUBREGISTRY,
                  roleBitmap: 0n,
                  resolver: RESOLVER,
                  expires: 0n,
                },
                toL1: false,
                salt: 0n,
              },
            ]),
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
  });
});
