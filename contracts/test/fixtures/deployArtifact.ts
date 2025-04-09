import hre from "hardhat";
import { readFile } from "node:fs/promises";
import {
    type Hex,
    type Abi,
    type Address,
    sliceHex,
    concat,
    getContractAddress,
} from "viem";

export function urgArtifact(name: string) {
    return new URL(
        `../../lib/unruggable-gateways/artifacts/${name}.sol/${name}.json`,
        import.meta.url
    );
}

export async function deployArtifact(options: {
    file: string | URL;
    from?: Hex;
    args?: any[];
    libs?: Record<string, Address>;
}) {
    const artifact = JSON.parse(await readFile(options.file, "utf8")) as {
        abi: Abi;
        bytecode: {
            object: Hex;
            linkReferences: Record<
                string,
                Record<string, { start: number; length: number }[]>
            >;
        };
    };
    let bytecode = artifact.bytecode.object;
    for (const ref of Object.values(artifact.bytecode.linkReferences)) {
        for (const [name, places] of Object.entries(ref)) {
            const lib = options.libs?.[name];
            if (!lib) throw new Error(`expected library: ${name}`);
            for (const { start, length } of places) {
                bytecode = concat([
                    sliceHex(bytecode, 0, start),
                    lib,
                    sliceHex(bytecode, start + length),
                ]);
            }
        }
    }
    const walletClient = options.from
        ? await hre.viem.getWalletClient(options.from)
        : await hre.viem.getWalletClients().then((x) => x[0]);
    const publicClient = await hre.viem.getPublicClient();
    const nonce = BigInt(
        await publicClient.getTransactionCount(walletClient.account)
    );
    const hash = await walletClient.deployContract({
        abi: artifact.abi,
        bytecode,
        args: options.args,
    });
    await publicClient.waitForTransactionReceipt({ hash });
    return getContractAddress({
        from: walletClient.account.address,
        nonce,
    });
}
