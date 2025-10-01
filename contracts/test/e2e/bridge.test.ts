import { afterAll, beforeAll, describe, expect, it } from "bun:test";
import {
  encodeAbiParameters,
  getAddress,
  parseAbiParameters,
  toHex,
  zeroAddress,
} from "viem";

import { ROLES } from "../../deploy/constants.js";
import { type MockRelayer, createMockRelay } from "../../script/mockRelay.js";
import {
  type CrossChainEnvironment,
  setupCrossChainEnvironment,
} from "../../script/setup.js";
import {
  dnsEncodeName,
  getCanonicalId,
  labelToCanonicalId,
} from "../integration/utils/utils.js";

describe("Bridge", () => {
  let env: CrossChainEnvironment;
  let relay: MockRelayer;
  beforeAll(async () => {
    env = await setupCrossChainEnvironment();
    relay = createMockRelay(env);
  });
  afterAll(() => env?.shutdown);
  // beforeEach(() => env?.resetState());

  it("name ejection", async () => {
    const label = "premium";
    const name = `${label}.eth`;
    const dnsEncodedName = dnsEncodeName(name);
    const user = env.accounts[1];
    const l1Owner = env.accounts[2];
    const l1Subregistry = env.l1.contracts.ethRegistry.address;
    const l1Resolver = zeroAddress;
    const expiryTime = BigInt(Math.floor(Date.now() / 1000) + 31536000); // 1 year from now
    const roleBitmap = ROLES.ALL;

    console.log("Registering the name on L2...");
    const registerTx = await env.l2.contracts.ethRegistry.write.register([
      label,
      user.address,
      env.l2.contracts.ethRegistry.address,
      zeroAddress,
      roleBitmap,
      expiryTime,
    ]);
    await env.l2.client.waitForTransactionReceipt({ hash: registerTx });
    console.log(`Name registered on L2, tx hash: ${registerTx}`);

    const [tokenId] = await env.l2.contracts.ethRegistry.read.getNameData([
      label,
    ]);
    console.log(`TokenID from registry: ${tokenId}`);

    const owner = await env.l2.contracts.ethRegistry.read.ownerOf([tokenId]);
    console.log(`Token owner: ${owner}`);

    const canonicalId = getCanonicalId(tokenId);
    console.log(`Canonical ID: ${canonicalId}`);

    console.log(`             Label: ${label}`);
    console.log(`    dnsEncodedname: ${dnsEncodedName}`);
    console.log(`           tokenId: ${toHex(tokenId, { size: 32 })}`);
    console.log(`       canonicalId: ${canonicalId}`);

    expect(canonicalId, "canonical").toStrictEqual(labelToCanonicalId(label));

    const encodedTransferData = encodeAbiParameters(
      parseAbiParameters("(bytes,address,address,address,uint256,uint64)"),
      [
        [
          dnsEncodedName,
          l1Owner.address,
          l1Subregistry,
          l1Resolver,
          roleBitmap,
          expiryTime,
        ],
      ],
    );

    console.log("L2 registry", env.l2.contracts.ethRegistry.address);
    console.log("L2 controller", env.l2.contracts.bridgeController.address);

    console.log("Transferring token to L2BridgeController...");
    await relay.waitFor(
      env.l2.contracts.ethRegistry.write.safeTransferFrom(
        [
          owner,
          env.l2.contracts.bridgeController.address,
          tokenId,
          1n,
          encodedTransferData,
        ],
        { account: owner },
      ),
    );

    console.log("Verifying registration on L1...");
    const actualL1Owner = await env.l1.contracts.ethRegistry.read.ownerOf([
      tokenId,
    ]);
    console.log(`Owner on L1: ${actualL1Owner}`);
    expect(actualL1Owner).toBe(l1Owner.address);
    console.log("✓ Name successfully registered on L1");

    // In assertions, use bridgeEvents[0].args.dnsEncodedName and bridgeEvents[0].args.data
  });

  it("round trip", async () => {
    const label = "roundtrip";
    const name = `${label}.eth`;
    const dnsEncodedName = dnsEncodeName(name);
    const l1User = env.accounts[1].address;
    const l2User = env.accounts[1].address;
    const l2Subregistry = env.l2.contracts.ethRegistry.address;
    const l1Subregistry = env.l1.contracts.ethRegistry.address;
    const resolver = zeroAddress;
    const expiryTime = BigInt(Math.floor(Date.now() / 1000) + 31536000); // 1 year from now
    const roleBitmap = ROLES.ALL;

    console.log("Registering the name on L2...");
    const registerTx = await env.l2.contracts.ethRegistry.write.register([
      label,
      l2User,
      l2Subregistry,
      resolver,
      roleBitmap,
      expiryTime,
    ]);
    await env.l2.client.waitForTransactionReceipt({ hash: registerTx });
    console.log(`Name registered on L2, tx hash: ${registerTx}`);

    const [tokenId] = await env.l2.contracts.ethRegistry.read.getNameData([
      label,
    ]);
    console.log(`TokenID from registry: ${tokenId}`);

    const encodedTransferDataToL1 = encodeAbiParameters(
      parseAbiParameters("(bytes,address,address,address,uint256,uint64)"),
      [
        [
          dnsEncodedName,
          l1User,
          l1Subregistry,
          resolver,
          roleBitmap,
          expiryTime,
        ],
      ],
    );

    await relay.waitFor(
      env.l2.contracts.ethRegistry.write.safeTransferFrom(
        [
          l2User,
          env.l2.contracts.bridgeController.address,
          tokenId,
          1n,
          encodedTransferDataToL1,
        ],
        { account: l1User },
      ),
    );

    const owner = await env.l1.contracts.ethRegistry.read.ownerOf([tokenId]);
    console.log(`Owner on L1: ${owner}`);
    console.log("✓ Name successfully registered on L1");
    expect(owner).toBe(l1User);

    const encodedTransferDataToL2 = encodeAbiParameters(
      parseAbiParameters("(bytes,address,address,address,uint256,uint64)"),
      [
        [
          dnsEncodedName,
          l2User,
          l2Subregistry,
          resolver,
          roleBitmap,
          expiryTime,
        ],
      ],
    );

    await relay.waitFor(
      env.l1.contracts.ethRegistry.write.safeTransferFrom(
        [
          l1User,
          env.l1.contracts.bridgeController.address,
          tokenId,
          1n,
          encodedTransferDataToL2,
        ],
        { account: l1User },
      ),
    );

    console.log("Verifying round trip results...");

    const finalL2Owner = await env.l2.contracts.ethRegistry.read.ownerOf([
      tokenId,
    ]);
    console.log(`Final owner on L2: ${finalL2Owner}`);
    expect(finalL2Owner).toBe(l2User);

    const subregistry = await env.l2.contracts.ethRegistry.read.getSubregistry([
      label,
    ]);
    console.log(`Subregistry on L2: ${subregistry}`);
    expect(subregistry).toBe(getAddress(l2Subregistry));

    // In assertions, use ejectionEvents[0].args.dnsEncodedName and ejectionEvents[0].args.data
  });
});
