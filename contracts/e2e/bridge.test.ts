import { afterAll, expect, test } from "bun:test";

import {
  encodeAbiParameters,
  getAddress,
  parseAbiParameters,
  zeroAddress,
} from "viem";
import { ROLES } from "../deploy/constants.js";
import { createMockRelay } from "../script/mockRelay.js";
import { setupCrossChainEnvironment } from "../script/setup.js";
import {
  expectTransactionSuccess,
  labelToCanonicalId,
  waitForEvent,
} from "./utils.js";

const { l1, l2, shutdown } = await setupCrossChainEnvironment();
afterAll(shutdown);
const relayer = createMockRelay({
  l1Bridge: l1.contracts.mockBridge,
  l2Bridge: l2.contracts.mockBridge,
  l1Client: l1.client,
  l2Client: l2.client,
});
afterAll(relayer.removeListeners);

test("name ejection", async () => {
  const label = "premium";
  const name = "premium.eth";
  const user = l2.accounts.deployer.address;
  const l1Owner = l1.accounts.deployer.address;
  const l1Subregistry = l1.contracts.ethRegistry.address;
  const l1Resolver = zeroAddress;
  const expiryTime = BigInt(Math.floor(Date.now() / 1000) + 31536000); // 1 year from now
  const roleBitmap = ROLES.ALL;

  console.log("Registering the name on L2...");
  const registerTx = l2.contracts.ethRegistry.write.register([
    label,
    user,
    l2.contracts.ethRegistry.address,
    zeroAddress,
    roleBitmap,
    expiryTime,
  ]);
  await expectTransactionSuccess(l2.client, registerTx);
  console.log(`Name registered on L2, tx hash: ${registerTx}`);

  const [tokenId] = await l2.contracts.ethRegistry.read.getNameData([label]);
  console.log(`TokenID from registry: ${tokenId}`);

  const owner = await l2.contracts.ethRegistry.read.ownerOf([tokenId]);
  console.log(`Token owner: ${owner}`);

  const canonicalId = await l2.contracts.ethRegistry.read.getTokenIdResource([
    tokenId,
  ]);
  console.log(`Canonical ID: ${canonicalId}`);

  const labelHash = labelToCanonicalId(label);
  console.log(`Label hash for "${label}": ${labelHash}`);
  console.log(`Token ID for "${label}": 0x${tokenId.toString(16)}`);
  console.log(`Does it match resource? ${labelHash === canonicalId}`);
  expect(labelHash).toBe(canonicalId);

  const transferDataParameters = [
    label,
    l1Owner,
    l1Subregistry,
    l1Resolver,
    roleBitmap,
    expiryTime,
  ] as const;

  const encodedData = encodeAbiParameters(
    parseAbiParameters("(string,address,address,address,uint256,uint64)"),
    [transferDataParameters],
  );

  console.log("L2 registry", l2.contracts.ethRegistry.address);
  console.log("L2 controller", l2.contracts.ejectionController.address);

  console.log("Transferring token to L2EjectionController...");
  const transferTx = l2.contracts.ethRegistry.write.safeTransferFrom([
    owner,
    l2.contracts.ejectionController.address,
    tokenId,
    1n,
    encodedData,
  ]);
  const ejectionEvents = await waitForEvent(
    l1.contracts.ejectionController.watchEvent.NameEjected,
  );
  await expectTransactionSuccess(l2.client, transferTx);
  console.log(
    `Token transferred to L2EjectionController, tx hash: ${transferTx}`,
  );

  if (ejectionEvents.length === 0) {
    console.log("No NameEjected event found on L1, performing manual relay");
    throw new Error(
      "No NameEjected event found on L1, performing manual relay",
    );
  } else {
    console.log("Name ejection event found on L1, automatic relay worked");
  }

  console.log("Verifying registration on L1...");
  const actualL1Owner = await l1.contracts.ethRegistry.read.ownerOf([tokenId]);
  console.log(`Owner on L1: ${actualL1Owner}`);
  console.log("✓ Name successfully registered on L1");
  expect(actualL1Owner).toBe(l1Owner);
});

test("round trip", async () => {
  const label = "roundtrip";
  const name = "roundtrip.eth";
  const l1User = l1.accounts.deployer.address;
  const l2User = l2.accounts.deployer.address;
  const l2Subregistry = l2.contracts.ethRegistry.address;
  const l1Subregistry = l1.contracts.ethRegistry.address;
  const resolver = zeroAddress;
  const expiryTime = BigInt(Math.floor(Date.now() / 1000) + 31536000); // 1 year from now
  const roleBitmap = ROLES.ALL;

  console.log("Registering the name on L2...");
  const registerTx = l2.contracts.ethRegistry.write.register([
    label,
    l2User,
    l2Subregistry,
    resolver,
    roleBitmap,
    expiryTime,
  ]);
  await expectTransactionSuccess(l2.client, registerTx);
  console.log(`Name registered on L2, tx hash: ${registerTx}`);

  const [tokenId] = await l2.contracts.ethRegistry.read.getNameData([label]);
  console.log(`TokenID from registry: ${tokenId}`);

  const transferDataParametersToL1 = [
    label,
    l1User,
    l1Subregistry,
    resolver,
    roleBitmap,
    expiryTime,
  ] as const;

  const encodedDataToL1 = encodeAbiParameters(
    parseAbiParameters("(string,address,address,address,uint256,uint64)"),
    [transferDataParametersToL1],
  );

  const transferTxToL1 = l2.contracts.ethRegistry.write.safeTransferFrom([
    l2User,
    l2.contracts.ejectionController.address,
    tokenId,
    1n,
    encodedDataToL1,
  ]);
  const ejectionEvents = await waitForEvent(
    l1.contracts.ejectionController.watchEvent.NameEjected,
  );
  await expectTransactionSuccess(l2.client, transferTxToL1);
  console.log(
    `Token transferred to L2EjectionController, tx hash: ${transferTxToL1}`,
  );

  if (ejectionEvents.length === 0) {
    throw new Error(
      "No NameEjected event found on L1, performing manual relay",
    );
  } else {
    console.log("Name ejection event found on L1, automatic relay worked");
  }

  const owner = await l1.contracts.ethRegistry.read.ownerOf([tokenId]);
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

  const encodedDataToL2 = encodeAbiParameters(
    parseAbiParameters("(string,address,address,address,uint256,uint64)"),
    [transferDataParametersToL2],
  );

  const transferTxToL2 = l1.contracts.ethRegistry.write.safeTransferFrom([
    l1User,
    l1.contracts.ejectionController.address,
    tokenId,
    1n,
    encodedDataToL2,
  ]);
  const migrationEvents = await waitForEvent(
    l2.contracts.ejectionController.watchEvent.NameMigrated,
  );
  await expectTransactionSuccess(l1.client, transferTxToL2);
  console.log(
    `Token transferred to L1EjectionController, tx hash: ${transferTxToL2}`,
  );

  if (migrationEvents.length === 0) {
    throw new Error(
      "No NameMigrated event found on L2, performing manual relay",
    );
  } else {
    console.log("Name migration event found on L2, automatic relay worked");
  }

  console.log("Verifying round trip results...");

  const finalL2Owner = await l2.contracts.ethRegistry.read.ownerOf([tokenId]);
  console.log(`Final owner on L2: ${finalL2Owner}`);
  expect(finalL2Owner).toBe(l2User);

  const subregistry = await l2.contracts.ethRegistry.read.getSubregistry([
    label,
  ]);
  console.log(`Subregistry on L2: ${subregistry}`);
  expect(subregistry).toBe(getAddress(l2Subregistry));
});
