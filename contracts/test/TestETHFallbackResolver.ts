import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers.js";
import { expect } from "chai";
import { deployEnsFixture } from "./fixtures/deployEnsFixture.js";
import { deployArtifact, urgArtifact } from "./fixtures/deployArtifact.js";
import { encodeErrorResult, namehash, parseAbi, zeroAddress } from "viem";
import { UncheckedRollup } from "../lib/unruggable-gateways/src/UncheckedRollup.js";
import { Gateway } from "../lib/unruggable-gateways/src/gateway.js";
import { dnsEncodeName, labelhashUint256, splitName } from "./utils/utils.js";
import { serve } from "@namestone/ezccip/serve";
import { BrowserProvider } from "ethers/providers";
import { makeResolutions } from "../lib/ens-contracts/test/universalResolver/utils.js";

async function fixture() {
    const mainnet = await deployEnsFixture(true);
    const namechain = await deployEnsFixture();
    const gateway = new Gateway(
        new UncheckedRollup(new BrowserProvider(hre.network.provider))
    );
    gateway.latestCache.cacheMs = 0;
    gateway.commitCacheMap.cacheMs = 0;
    gateway.callLRU.max = 0;
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
            namechain.ethRegistry.address,
            verifierAddress,
        ]
    );
    await mainnet.rootRegistry.write.setResolver([
        labelhashUint256("eth"),
        ETHFallbackRegistry.address,
    ]);
    const publicResolver = await hre.viem.deployContract("PublicResolver");
    return {
        ETHFallbackRegistry,
        publicResolver,
        mainnet,
        namechain,
        ensureRegistry,
    };
    async function ensureRegistry(
        name: string,
        owner = namechain.accounts[0].address
    ) {
        const labels = splitName(name);
        if (labels.pop() !== "eth") throw new Error("expected eth");
        if (!labels.length) throw new Error("expected 2LD+");
        const eth = labels.pop()!;
        const exp = (1n << 64n) - 1n;
        if (!labels.length) {
            await namechain.ethRegistry.write.register([
                eth,
                owner,
                zeroAddress,
                publicResolver.address,
                0n,
                exp,
            ]);
        } else {
            let userRegistry = await hre.viem.deployContract(
                "MockUserRegistry",
                [
                    namechain.ethRegistry.address,
                    eth,
                    namechain.datastore.address,
                ]
            );
            await namechain.ethRegistry.write.register([
                eth,
                owner,
                userRegistry.address,
                zeroAddress,
                0n,
                exp,
            ]);
            for (let i = labels.length - 1; i > 0; i--) {
                const registry = await hre.viem.deployContract(
                    "MockUserRegistry",
                    [
                        userRegistry.address,
                        labels[i - 1],
                        namechain.datastore.address,
                    ]
                );
                await userRegistry.write.mint([
                    labels[i],
                    owner,
                    registry.address,
                    0n,
                ]);
                userRegistry = registry;
            }
            await userRegistry.write.setResolver([
                labelhashUint256(labels[0]),
                publicResolver.address,
            ]);
        }
    }
}

const testAddress = "0x8000000000000000000000000000000000000001";

describe("ETHFallbackResolver", () => {
    describe("not ejected: resolver unset", () => {
        for (const name of ["eth", "test.eth", "sub.test.eth"]) {
            it(name, async () => {
                const F = await loadFixture(fixture);
                const [res] = makeResolutions({
                    name,
                    addresses: [{ coinType: 60n, encodedAddress: testAddress }],
                });
                await expect(F.mainnet.universalResolver)
                    .read("resolve", [dnsEncodeName(name), res.call])
                    .toBeRevertedWithCustomError("ResolverError")
                    .withArgs(
                        encodeErrorResult({
                            abi: parseAbi(["error UnreachableName(bytes)"]),
                            args: [dnsEncodeName(name)],
                        })
                    );
            });
        }
    });

    describe("not ejected: resolver set", () => {
        for (const name of ["test.eth", "sub.test.eth"]) {
            it(name, async () => {
                const F = await loadFixture(fixture);
                await F.ensureRegistry(name);
                await F.publicResolver.write.setAddr([
                    namehash(name),
                    60n,
                    testAddress,
                ]);
                const [res] = makeResolutions({
                    name,
                    addresses: [
                        {
                            coinType: 60n,
                            encodedAddress: testAddress,
                        },
                    ],
                });
                const [answer, resolver] =
                    await F.mainnet.universalResolver.read.resolve([
                        dnsEncodeName(name),
                        res.call,
                    ]);
                expect(resolver).toEqualAddress(F.ETHFallbackRegistry.address);
                res.expect(answer);
            });
        }
    });
});
