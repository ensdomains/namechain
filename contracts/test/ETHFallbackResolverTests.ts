import type { NamedContractReturnType } from "@ensdomains/hardhat-chai-matchers-viem";
import { shouldSupportInterfaces } from "@ensdomains/hardhat-chai-matchers-viem/behaviour";
import { FEATURES } from "./utils/features.js";
import { describe, it } from "vitest";
import {
  COIN_TYPE_ETH,
  KnownProfile,
  makeResolutions,
} from "./utils/resolutions.js";
import { dnsEncodeName, expectVar } from "./utils/utils.js";
import { ArtifactMap } from "hardhat/types/artifacts";
import { Client, GetContractReturnType } from "viem";
import { expect } from "chai";

type Deployment = Readonly<{
  ethFallbackResolver: NamedContractReturnType<"ETHFallbackResolver">;
  ethResolver: NamedContractReturnType<"DedicatedResolver">;
  mainnetV1: {
    universalResolver: NamedContractReturnType<"UniversalResolver">;
  };
  mainnetV2: {
    universalResolver: NamedContractReturnType<"UniversalResolver">;
  };
  sync(): Promise<void>;
}>;

const dummySelector = "0x12345678";
const testAddress = "0x8000000000000000000000000000000000000001";
const testNames = ["test.eth", "a.b.c.test.eth"];

export function createETHFallbackTests(loadFixture: () => Promise<Deployment>) {
  return () => {
   
    shouldSupportInterfaces({
      contract: () => loadFixture().then((F) => F.ethFallbackResolver),
      interfaces: ["IERC165", "IExtendedResolver", "IFeatureSupporter"],
    });

    it("supportsFeature: resolve(multicall)", async () => {
      const F = await loadFixture();
      await expect(
        F.ethFallbackResolver.read.supportsFeature([
          FEATURES.RESOLVER.RESOLVE_MULTICALL,
        ]),
      ).resolves.toStrictEqual(true);
    });
    

    it("eth", async () => {
      const F = await loadFixture();
      const kp: KnownProfile = {
        name: "eth",
        addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }],
      };
      const [res] = makeResolutions(kp);
      await F.ethResolver.write.multicall([[res.writeDedicated]]);
      await F.sync();
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(kp.name),
          res.call,
        ]);
      expectVar({ resolver }).toEqualAddress(F.ethFallbackResolver.address);
      res.expect(answer);
    });

    /*
    describe("unregistered", () => {
      for (const name of testNames) {
        it(name, async () => {
          const F = await loadFixture();
          const [res] = makeResolutions({
            name,
            addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }],
          });
          await F.sync();
          await expect(
            F.mainnetV1.universalResolver.read.resolve([
              dnsEncodeName(name),
              res.call,
            ]),
          ).toBeRevertedWithCustomError("ResolverNotFound");
          // the errors are different because:
          // V1: requireResolver() fails
          // V2: gateway to namechain, no resolver found
          await expect(
            F.mainnetV2.universalResolver.read.resolve([
              dnsEncodeName(name),
              res.call,
            ]),
          )
            .toBeRevertedWithCustomError("ResolverError")
            .withArgs(
              encodeErrorResult({
                abi: F.ethFallbackResolver.abi,
                errorName: "UnreachableName",
                args: [dnsEncodeName(name)],
              }),
            );
        });
      }
    });

    describe("still registered on V1", () => {
      for (const name of testNames) {
        it(name, async () => {
          const F = await loadFixture();
          const kp: KnownProfile = {
            name,
            addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }],
          };
          const [res] = makeResolutions(kp);
          await F.mainnetV1.setupName(kp.name);
          await F.mainnetV1.walletClient.sendTransaction({
            to: F.mainnetV1.ownedResolver.address,
            data: res.write, // V1 OwnedResolver lacks multicall()
          });
          await F.sync();
          const [answer, resolver] =
            await F.mainnetV2.universalResolver.read.resolve([
              dnsEncodeName(kp.name),
              res.call,
            ]);
          expectVar({ resolver }).toEqualAddress(F.ethFallbackResolver.address);
          res.expect(answer);
        });
      }
    });
    */
  };
}
