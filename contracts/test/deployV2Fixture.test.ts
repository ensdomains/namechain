import hre from "hardhat";
import { zeroAddress, type Address } from "viem";
import { describe, expect, it, afterAll } from "vitest";

import { deployV2Fixture, ROLES } from "./fixtures/deployV2Fixture.ts";
import { expectVar } from "./utils/expectVar.ts";
import { labelToCanonicalId } from "./utils/utils.ts";
import { injectCoverage } from "./utils/hardhat-coverage.js";

const saveCoverage = injectCoverage("deployV2Fixture");

const chain = await hre.network.connect();
async function fixture() {
  return deployV2Fixture(chain);
}
const loadFixture = async () => chain.networkHelpers.loadFixture(fixture);

const testAddress = "0x8000000000000000000000000000000000000001";

function expectRegistries(
  actual: ({ address: Address } | undefined)[],
  expected: typeof actual,
) {
  expect(actual, "registries.length").toHaveLength(expected.length);
  actual.forEach((x, i) => {
    expect(x?.address.toLowerCase(), `registry[${i}]`).toEqual(
      expected[i]?.address.toLowerCase(),
    );
  });
}

describe("deployV2Fixture", () => {
    afterAll(() => saveCoverage?.());
  
  it("setupName()", async () => {
    const F = await loadFixture();
    const {
      labels,
      tokenId,
      parentRegistry,
      exactRegistry,
      registries,
      dedicatedResolver,
    } = await F.setupName({
      name: "test.eth",
    });
    expectVar({ labels }).toStrictEqual(["test", "eth"]);
    expectVar({ tokenId }).toEqual(labelToCanonicalId("test"));
    expectVar({ parentRegistry }).toEqual(registries[1]);
    expectVar({ exactRegistry }).toBeUndefined();
    expectVar({ dedicatedResolver }).toBeDefined();
    expectRegistries(registries, [undefined, F.ethRegistry, F.rootRegistry]);
  });

  it("setupName() w/exact", async () => {
    const F = await loadFixture();
    const { labels, tokenId, parentRegistry, exactRegistry, registries } =
      await F.setupName({
        name: "test.eth",
        exact: true,
      });
    expectVar({ labels }).toStrictEqual(["test", "eth"]);
    expectVar({ tokenId }).toEqual(labelToCanonicalId("test"));
    expectVar({ parentRegistry }).toEqual(registries[1]);
    expectVar({ exactRegistry }).toBeDefined();
    expectRegistries(registries, [
      exactRegistry,
      F.ethRegistry,
      F.rootRegistry,
    ]);
  });

  it("setupName() w/resolver", async () => {
    const F = await loadFixture();
    const { dedicatedResolver } = await F.setupName({
      name: "test.eth",
      resolverAddress: zeroAddress,
    });
    expectVar({ dedicatedResolver }).toBeUndefined();
  });

  it("overlapping names", async () => {
    const F = await loadFixture();
    await F.setupName({ name: "test.eth" });
    await F.setupName({ name: "a.b.c.sub.test.eth" });
    await F.setupName({ name: "sub.test.eth" });
  });

  it("arbitrary names", async () => {
    const F = await loadFixture();
    await F.setupName({ name: "xyz" });
    await F.setupName({ name: "chonk.box" });
    await F.setupName({ name: "ens.domains" });
  });

  it("locked resolver", async () => {
    const F = await loadFixture();
    const { parentRegistry, tokenId } = await F.setupName({
      name: "locked.test.eth",
      roles: ROLES.ALL & ~ROLES.OWNER.EAC.SET_RESOLVER,
    });
    await parentRegistry.write.setSubregistry([tokenId, testAddress]);
    await expect(
      parentRegistry.write.setResolver([tokenId, testAddress]),
    ).toBeRevertedWithCustomError("EACUnauthorizedAccountRoles");
  });

  it("locked registry", async () => {
    const F = await loadFixture();
    const { parentRegistry, tokenId } = await F.setupName({
      name: "locked.test.eth",
      roles: ROLES.ALL & ~ROLES.OWNER.EAC.SET_SUBREGISTRY,
    });
    await parentRegistry.write.setResolver([tokenId, testAddress]);
    await expect(
      parentRegistry.write.setSubregistry([tokenId, testAddress]),
    ).toBeRevertedWithCustomError("EACUnauthorizedAccountRoles");
  });
});
