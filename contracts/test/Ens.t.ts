import { loadFixture } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers.js";
import { expect } from "chai";
import { deployV2Fixture, ROLES } from "./fixtures/deployV2Fixture.js";
import { dnsEncodeName } from "./utils/utils.js";

const testAddress = "0x8000000000000000000000000000000000000001";

describe("Ens", () => {
  it("returns eth registry for eth", async () => {
    const F = await loadFixture(deployV2Fixture);
    const [ethRegistry, isExact] = await F.universalResolver.read.getRegistry([
      dnsEncodeName("eth"),
    ]);
    expect(isExact).toBe(true);
    expect(ethRegistry).toEqualAddress(F.ethRegistry.address);
  });

  it("returns eth registry for test.eth without user registry", async () => {
    const F = await loadFixture(deployV2Fixture);
    const name = "test.eth";
    await F.setupName({ name });
    const [registry, isExact] = await F.universalResolver.read.getRegistry([
      dnsEncodeName(name),
    ]);
    expect(isExact).toBe(false);
    expect(registry).toEqualAddress(F.ethRegistry.address);
  });

  it("exact", async () => {
    const F = await loadFixture(deployV2Fixture);
    const name = "test.eth";
    const { registries } = await F.setupName({ name, exact: true });
    const [registry, isExact] = await F.universalResolver.read.getRegistry([
      dnsEncodeName(name),
    ]);
    expect(isExact).toBe(true);
    expect(registry).toEqualAddress(registries[registries.length - 1].address);
  });

  it("overlapping names", async () => {
    const F = await loadFixture(deployV2Fixture);
    await F.setupName({ name: "test.eth" });
    await F.setupName({ name: "a.b.c.sub.test.eth" });
    await F.setupName({ name: "sub.test.eth" });
  });

  it("arbitrary names", async () => {
    const F = await loadFixture(deployV2Fixture);
    await F.setupName({ name: "xyz" });
    await F.setupName({ name: "chonk.box" });
    await F.setupName({ name: "ens.domains" });
  });

  it("locked resolver", async () => {
    const F = await loadFixture(deployV2Fixture);
    const { parentRegistry, tokenId } = await F.setupName({
      name: "locked.test.eth",
      roles: ROLES.ALL & ~ROLES.OWNER.EAC.SET_RESOLVER,
    });
    await parentRegistry.write.setSubregistry([tokenId, testAddress]);
    await expect(parentRegistry)
      .write("setResolver", [tokenId, testAddress])
      .toBeRevertedWithCustomError("EACUnauthorizedAccountRoles");
  });

  it("locked registry", async () => {
    const F = await loadFixture(deployV2Fixture);
    const { parentRegistry, tokenId } = await F.setupName({
      name: "locked.test.eth",
      roles: ROLES.ALL & ~ROLES.OWNER.EAC.SET_SUBREGISTRY,
    });
    await parentRegistry.write.setResolver([tokenId, testAddress]);
    await expect(parentRegistry)
      .write("setSubregistry", [tokenId, testAddress])
      .toBeRevertedWithCustomError("EACUnauthorizedAccountRoles");
  });
});
