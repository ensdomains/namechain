import hre from "hardhat";
import { describe, it } from "vitest";
import { deployV2Fixture } from "../fixtures/deployV2Fixture.js";
import { bundleCalls, makeResolutions } from "../utils/resolutions.js";
import { dnsEncodeName, expectVar } from "../utils/utils.js";
import { dummyShapeshiftResolverArtifact } from "../fixtures/ens-contracts/DummyShapeshiftResolver.js";

const chain = await hre.network.connect();

async function fixture() {
  const F = await deployV2Fixture(chain, true);
  const ssResolver = await chain.viem.deployContract(
    dummyShapeshiftResolverArtifact,
  );
  const mockNestedResolver = await chain.viem.deployContract(
    "MockNestedResolver",
    [F.universalResolver.address],
  );
  return { ...F, ssResolver, mockNestedResolver };
}

// NOTE: most tests are in ens-contracts/
describe("UniversalResolver", () => {
  it("UR -> UR", async () => {
    const F = await chain.networkHelpers.loadFixture(fixture);
    const name = "test.eth";
    await F.setupName({ name, resolverAddress: F.mockNestedResolver.address });
    await F.setupName({
      name: `nested.${name}`,
      resolverAddress: F.ssResolver.address,
    });
    const bundle = bundleCalls(
      makeResolutions({
        name,
        addresses: [{ coinType: 1n, value: "0x1234" }],
        texts: [{ key: "abc", value: "def" }],
      }),
    );
    await F.ssResolver.write.setOffchain([true]);
    for (const res of bundle.resolutions) {
      await F.ssResolver.write.setResponse([res.call, res.answer]);
    }
    const [answer, resolver] = await F.universalResolver.read.resolve([
      dnsEncodeName(name),
      bundle.call,
    ]);
    expectVar({ resolver }).toEqualAddress(F.mockNestedResolver.address);
    bundle.expect(answer);
  });
});
