import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers.js";
import { expect } from "chai";
import { deployEnsFixture } from "./fixtures/deployEnsFixture.js";
import { deployArtifact } from "./fixtures/deployArtifact.js";
import { namehash, zeroAddress } from "viem";
import { UncheckedRollup } from "../lib/unruggable-gateways/src/UncheckedRollup.js";
import { Gateway } from "../lib/unruggable-gateways/src/gateway.js";
import { dnsEncodeName, labelhashUint256 } from "./utils/utils.js";
import { serve } from "@namestone/ezccip/serve";
import { BrowserProvider } from "ethers/providers";
import {
  KnownProfile,
  makeResolutions,
} from "../lib/ens-contracts/test/universalResolver/utils.js";

function urgArtifact(name: string) {
  return new URL(
    `../lib/unruggable-gateways/artifacts/${name}.sol/${name}.json`,
    import.meta.url
  );
}

async function fixture() {
  const mainnet = await deployEnsFixture(true);
  const namechain = await deployEnsFixture();
  const gateway = new Gateway(
    new UncheckedRollup(new BrowserProvider(hre.network.provider))
  );
  const ccip = await serve(gateway, { protocol: "raw", log: false });
  after(ccip.shutdown);
  const GatewayVM = await deployArtifact({
    file: urgArtifact("GatewayVM"),
  });
  const verifierAddress = await deployArtifact({
    file: urgArtifact("UncheckedVerifier"),
    args: [[ccip.endpoint]],
    libs: { GatewayVM },
  });
  const ETHFallbackRegistry = await hre.viem.deployContract(
    "ETHFallbackResolver",
    [
      mainnet.rootRegistry.address,
      namechain.datastore.address,
      namechain.rootRegistry.address,
      verifierAddress,
    ]
  );
  await mainnet.rootRegistry.write.setResolver([
    labelhashUint256("eth"),
    ETHFallbackRegistry.address,
  ]);
  const publicResolver = await hre.viem.deployContract("PublicResolver");
  return { ETHFallbackRegistry, publicResolver, mainnet, namechain };
}

describe("ETHFallbackResolver", () => {
  it("not ejected", async () => {
    const F = await loadFixture(fixture);
    const label = "raffy";
    const kp: KnownProfile = {
      name: `${label}.eth`,
      addresses: [
        {
          coinType: 60n,
          encodedAddress:
            "0x51050ec063d393217B436747617aD1C2285Aeeee",
        },
      ],
    };
    await F.namechain.ethRegistry.write.register([
      label,
      F.namechain.accounts[0].address,
      zeroAddress,
      F.publicResolver.address,
      0n,
      (1n << 64n) - 1n,
    ]);
    await F.publicResolver.write.setAddr([
      namehash(kp.name),
      kp.addresses![0].coinType,
      kp.addresses![0].encodedAddress,
    ]);
    const [res] = makeResolutions(kp);
    const [answer, resolver] =
      await F.mainnet.universalResolver.read.resolve([
        dnsEncodeName(kp.name),
        res.call,
      ]);
    expect(resolver).toEqualAddress(F.ETHFallbackRegistry.address);
    res.expect(answer);
  });
});
