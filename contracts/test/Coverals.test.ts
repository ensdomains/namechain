import hre from "hardhat";
import { describe, it } from "vitest";

const chain = await hre.network.connect();
async function fixture() {
  return chain.viem.deployContract("Coveralls", [], {
    client: {
      public: await chain.viem.getPublicClient({
        ccipRead: undefined,
      }),
    },
  });
}
const loadF = async () => chain.networkHelpers.loadFixture(fixture);

describe("Coveralls", () => {
  it("a", async () => {
    const F = await loadF();
    await F.read.a();
  });

  it("b", async () => {
    const F = await loadF();
    await F.write.b();
  });

  it("c", async () => {
    const F = await loadF();
    await F.read.c();
  });

  it("d", async () => {
    const F = await loadF();
    await F.read.d();
  });
});
