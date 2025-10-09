import { describe, it, beforeAll, beforeEach, afterAll } from "bun:test";
import { encodeAbiParameters } from "viem";

import {
  type CrossChainEnvironment,
  type CrossChainSnapshot,
  setupCrossChainEnvironment,
} from "../../script/setup.js";
import { type MockRelay, setupMockRelay } from "../../script/mockRelay.js";
import { ROLES } from "../../deploy/constants.js";

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

// https://www.notion.so/enslabs/ENS-v2-Design-Doc-291bb4ab8b26440fbbac46d1aaba1b83
// https://www.notion.so/enslabs/ENSv2-Migration-Plan-23b7a8b1f0ed80ee832df953abc80810

const SUBREGISTRY = "0x1111111111111111111111111111111111111111";
const RESOLVER = "0x2222222222222222222222222222222222222222";

// TODO: finish this after migration tests
describe("Ejection", () => {
  let env: CrossChainEnvironment;
  let relay: MockRelay;
  let resetState: CrossChainSnapshot;
  beforeAll(async () => {
    env = await setupCrossChainEnvironment({ procLog: true });
    relay = setupMockRelay(env);
    resetState = await env.saveState();
  });

  afterAll(() => env?.shutdown());
  beforeEach(() => resetState?.());

  it("2LD => L1", async () => {
    const account = env.namedAccounts.user2;
    const label = "test";
    const expiry = BigInt(Math.floor(Date.now() / 1000) + 86400);
    await env.l2.contracts.ETHRegistry.write.register([
      label,
      account.address,
      SUBREGISTRY,
      RESOLVER,
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
              subregistry: SUBREGISTRY,
              resolver: RESOLVER,
              roleBitmap: ROLES.ETH_REGISTRY,
              expiry,
            },
          ]),
        ],
        { account },
      ),
    );
  });
});
