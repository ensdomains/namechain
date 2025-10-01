import { toFunctionSelector, type Hex } from "viem";
import { describe, expect, it } from "vitest";
import { FEATURES } from "../../lib/ens-contracts/test/utils/features.js";

type FeatureKeys<T> = {
  [K in keyof T]?: readonly (keyof T[K])[];
};

export function shouldSupportFeatures({
  contract,
  features,
}: {
  contract: () => Promise<{
    read: {
      supportsFeature: (args: [Hex]) => Promise<boolean>;
      supportsInterface: (args: [Hex]) => Promise<boolean>;
    };
  }>;
  features: FeatureKeys<typeof FEATURES>;
}) {
  describe("IERC7996", () => {
    it("supports IERC165", async () => {
      const C = await contract();
      await expect(
        C.read.supportsInterface([
          toFunctionSelector("function supportsFeature(bytes4)"),
        ]),
      ).resolves.toStrictEqual(true);
    });
    for (const [family, keys] of Object.entries(features)) {
      describe(family, () => {
        const features = FEATURES[family as keyof typeof FEATURES];
        for (const key of keys) {
          it(`supports ${key}`, async () => {
            const C = await contract();
            await expect(
              C.read.supportsFeature([features[key as keyof typeof features]]),
            ).resolves.toStrictEqual(true);
          });
        }
      });
    }
  });
}
