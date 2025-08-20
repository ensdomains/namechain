import { describe, afterAll, beforeAll, expect, it } from "bun:test";
import {
  encodeAbiParameters,
  getAddress,
  labelhash,
  parseAbiParameters,
  toHex,
  zeroAddress,
} from "viem";

import { ROLES } from "../deploy/constants.js";
import { type MockRelayer, createMockRelay } from "../script/mockRelay.js";
import {
  type CrossChainEnvironment,
  setupCrossChainEnvironment,
} from "../script/setup.js";
import { expectTransactionSuccess, waitForEvent } from "./utils.js";
import { labelToCanonicalId, getCanonicalId } from "../test/utils/utils.ts";

describe("Bridge", () => {
  let env: CrossChainEnvironment;
  let relay: MockRelayer;
  beforeAll(async () => {
    env = await setupCrossChainEnvironment();
    afterAll(env.shutdown);
    relay = createMockRelay(env);
    afterAll(relay.removeListeners);
  });

  it("name ejection", async () => {
    const label = "premium";
    //const name = "premium.eth";
    const user = env.accounts[1];
    const l1Owner = env.accounts[2];
    const l1Subregistry = env.l1.contracts.ETHRegistry.address;
    const l1Resolver = zeroAddress;
    const expiryTime = BigInt(Math.floor(Date.now() / 1000) + 31536000); // 1 year from now
    const roleBitmap = ROLES.ALL;

    console.log("Registering the name on L2...");
    const registerTx = env.l2.contracts.ETHRegistry.write.register([
      label,
      user.address,
      zeroAddress,
      zeroAddress,
      roleBitmap,
      expiryTime,
    ]);
    await expectTransactionSuccess(env.l2.client, registerTx);
    console.log(`Name registered on L2, tx hash: ${await registerTx}`);

    const [tokenId] = await env.l2.contracts.ETHRegistry.read.getNameData([
      label,
    ]);
    console.log(`TokenID from registry: ${tokenId}`);

    const owner = await env.l2.contracts.ETHRegistry.read.ownerOf([tokenId]);
    console.log(`Token owner: ${owner}`);

    const canonicalId = getCanonicalId(tokenId);
    console.log(`Canonical ID: ${canonicalId}`);

    console.log(`      Label: ${label}`);
    console.log(`  labelHash: ${labelhash(label)}`);
    console.log(`    tokenId: ${toHex(tokenId, { size: 32 })}`);
    console.log(`canonicalId: ${canonicalId}`);

    expect(canonicalId, "canonical").toStrictEqual(labelToCanonicalId(label));

    const transferDataParameters = [
      label,
      l1Owner.address,
      l1Subregistry,
      l1Resolver,
      roleBitmap,
      expiryTime,
    ] as const;
    const encodedTransferData = encodeAbiParameters(
      parseAbiParameters("(string,address,address,address,uint256,uint64)"),
      [transferDataParameters],
    );

    console.log("L2 registry", env.l2.contracts.ETHRegistry.address);
    console.log("L2 controller", env.l2.contracts.L2BridgeController.address);

    console.log("Transferring token to L2BridgeController...");
	await relay.waitFor(env.l2.contracts.ETHRegistry.write.safeTransferFrom(
      [
        owner,
        env.l2.contracts.L2BridgeController.address,
        tokenId,
        1n,
        encodedTransferData,
      ],
      { account: owner },
    ));

    // // Wait for the NameBridgedToL1 event from L2 bridge (indicating ejection message sent)
    // const bridgeEvents = await waitForEvent(({ onLogs }) =>
    //   env.l2.contracts.MockL2Bridge.watchEvent.NameBridgedToL1({ onLogs }),
    // );
    // await expectTransactionSuccess(env.l2.client, transferTx);
    // console.log(
    //   `Token transferred to L2BridgeController, tx hash: ${await transferTx}`,
    // );

    // if ((bridgeEvents as any[]).length === 0) {
    //   console.log(
    //     "No NameBridgedToL1 event found on L2, manual relay might be needed",
    //   );
    //   throw new Error(
    //     "No NameBridgedToL1 event found on L2, manual relay might be needed",
    //   );
    // } else {
    //   console.log(
    //     "NameBridgedToL1 event found on L2, automatic relay should work",
    //   );
    // }

    // // Add a delay to allow the relay transaction to complete
    // console.log("Waiting for relay to complete...");
    // await new Promise((resolve) => setTimeout(resolve, 2000));

    console.log("Verifying registration on L1...");
    const actualL1Owner = await env.l1.contracts.ETHRegistry.read.ownerOf([
      tokenId,
    ]);
    console.log(`Owner on L1: ${actualL1Owner}`);
    expect(actualL1Owner).toBe(l1Owner.address);
    console.log("✓ Name successfully registered on L1");

    // In assertions, use bridgeEvents[0].args.dnsEncodedName and bridgeEvents[0].args.data
  });

  it("round trip", async () => {
    const label = "roundtrip";
    //const name = "roundtrip.eth";
    const l1User = env.accounts[1].address;
    const l2User = env.accounts[1].address;
    const l2Subregistry = env.l2.contracts.ETHRegistry.address;
    const l1Subregistry = env.l1.contracts.ETHRegistry.address;
    const resolver = zeroAddress;
    const expiryTime = BigInt(Math.floor(Date.now() / 1000) + 31536000); // 1 year from now
    const roleBitmap = ROLES.ALL;

    console.log("Registering the name on L2...");
    const registerTx = env.l2.contracts.ETHRegistry.write.register([
      label,
      l2User,
      l2Subregistry,
      resolver,
      roleBitmap,
      expiryTime,
    ]);
    await expectTransactionSuccess(env.l2.client, registerTx);
    console.log(`Name registered on L2, tx hash: ${await registerTx}`);

    const [tokenId] = await env.l2.contracts.ETHRegistry.read.getNameData([
      label,
    ]);
    console.log(`TokenID from registry: ${tokenId}`);

    const transferDataParametersToL1 = [
      label,
      l1User,
      l1Subregistry,
      resolver,
      roleBitmap,
      expiryTime,
    ] as const;
    const encodedTransferDataToL1 = encodeAbiParameters(
      parseAbiParameters("(string,address,address,address,uint256,uint64)"),
      [transferDataParametersToL1],
    );

	await relay.waitFor(env.l2.contracts.ETHRegistry.write.safeTransferFrom(
      [
        l2User,
        env.l2.contracts.L2BridgeController.address,
        tokenId,
        1n,
        encodedTransferDataToL1,
      ],
      { account: l1User },
    ));

    // // Wait for the NameBridgedToL1 event from L2 bridge (indicating ejection message sent)
    // const ejectionEvents = await waitForEvent(({ onLogs }) =>
    //   env.l2.contracts.MockL2Bridge.watchEvent.NameBridgedToL1({ onLogs }),
    // );
    // await expectTransactionSuccess(env.l2.client, transferTxToL1);
    // console.log(
    //   `Token transferred to L2BridgeController, tx hash: ${await transferTxToL1}`,
    // );

    // if ((ejectionEvents as any[]).length === 0) {
    //   throw new Error(
    //     "No NameBridgedToL1 event found on L2, manual relay might be needed",
    //   );
    // } else {
    //   console.log(
    //     "NameBridgedToL1 event found on L2, automatic relay should work",
    //   );
    // }

    // // Add a delay to allow the relay transaction to complete
    // console.log("Waiting for L2->L1 relay to complete...");
    // await new Promise((resolve) => setTimeout(resolve, 2000));

    const owner = await env.l1.contracts.ETHRegistry.read.ownerOf([tokenId]);
    console.log(`Owner on L1: ${owner}`);
    console.log("✓ Name successfully registered on L1");
    expect(owner).toBe(l1User);

    const transferDataParametersToL2 = [
      label,
      l2User,
      l2Subregistry,
      resolver,
      roleBitmap,
      expiryTime,
    ] as const;

    const encodedTransferDataToL2 = encodeAbiParameters(
      parseAbiParameters("(string,address,address,address,uint256,uint64)"),
      [transferDataParametersToL2],
    );

    await relay.waitFor(env.l1.contracts.ETHRegistry.write.safeTransferFrom(
      [
        l1User,
        env.l1.contracts.L1EjectionController.address,
        tokenId,
        1n,
        encodedTransferDataToL2,
      ],
      { account: l1User },
    ));

    // // Wait for the NameBridgedToL2 event from L1 bridge (indicating ejection message sent)
    // const migrationEvents = await waitForEvent(({ onLogs }) =>
    //   env.l1.contracts.MockL1Bridge.watchEvent.NameBridgedToL2({ onLogs }),
    // );
    // await expectTransactionSuccess(env.l1.client, transferTxToL2);
    // console.log(
    //   `Token transferred to L1EjectionController, tx hash: ${await transferTxToL2}`,
    // );

    // if ((migrationEvents as any[]).length === 0) {
    //   throw new Error(
    //     "No NameBridgedToL2 event found on L1, manual relay might be needed",
    //   );
    // } else {
    //   console.log(
    //     "NameBridgedToL2 event found on L1, automatic relay should work",
    //   );
    // }

    // // Add a delay to allow the relay transaction to complete
    // console.log("Waiting for L1->L2 relay to complete...");
    // await new Promise((resolve) => setTimeout(resolve, 2000));

    console.log("Verifying round trip results...");

    const finalL2Owner = await env.l2.contracts.ETHRegistry.read.ownerOf([
      tokenId,
    ]);
    console.log(`Final owner on L2: ${finalL2Owner}`);
    expect(finalL2Owner).toBe(l2User);

    const subregistry = await env.l2.contracts.ETHRegistry.read.getSubregistry([
      label,
    ]);
    console.log(`Subregistry on L2: ${subregistry}`);
    expect(subregistry).toBe(getAddress(l2Subregistry));

    // In assertions, use ejectionEvents[0].args.dnsEncodedName and ejectionEvents[0].args.data
  });
});
