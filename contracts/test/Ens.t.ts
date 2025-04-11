import { loadFixture } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers.js";
import { expect } from "chai";
import { deployV2Fixture, registerName } from "./fixtures/deployV2Fixture.js";
import { dnsEncodeName } from "./utils/utils.js";

describe("Ens", () => {
  it("returns eth registry for eth", async () => {
    const { universalResolver, ethRegistry } =
      await loadFixture(deployV2Fixture);
    const [fetchedEthRegistry, isExact] =
      await universalResolver.read.getRegistry([dnsEncodeName("eth")]);
    expect(isExact).toBe(true);
    expect(fetchedEthRegistry).toEqualAddress(ethRegistry.address);
  });

  it("returns eth registry for test.eth without user registry", async () => {
    const { universalResolver, ethRegistry } =
      await loadFixture(deployV2Fixture);
    await registerName({ ethRegistry, label: "test" });
    const [registry, isExact] = await universalResolver.read.getRegistry([
      dnsEncodeName("test.eth"),
    ]);
    expect(isExact).toBe(false);
    expect(registry).toEqualAddress(ethRegistry.address);
  });
});
