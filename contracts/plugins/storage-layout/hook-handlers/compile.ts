import { readFile, writeFile } from "fs/promises";
import type { Artifact } from "hardhat/types/artifacts";
import type { SolidityHooks } from "hardhat/types/hooks";
import type { SolidityBuildInfoOutput } from "hardhat/types/solidity";
import { dirname, join } from "path";

import type { StorageLayout } from "../types.ts";

export default async (): Promise<Partial<SolidityHooks>> => {
  const handlers: Partial<SolidityHooks> = {
    onCleanUpArtifacts: async (context, artifactFiles) => {
      const buildInfoOutputCache = new Map<string, SolidityBuildInfoOutput>();
      for (const fileName of artifactFiles) {
        const file = await readFile(fileName, "utf-8");
        const json = JSON.parse(file) as Artifact;
        const buildInfoId = json.buildInfoId!;
        let buildInfoOutput: SolidityBuildInfoOutput;
        if (buildInfoOutputCache.has(buildInfoId))
          buildInfoOutput = buildInfoOutputCache.get(buildInfoId)!;
        else {
          const buildInfoOutputPath =
            (await context.artifacts.getBuildInfoOutputPath(buildInfoId))!;
          buildInfoOutput = JSON.parse(
            await readFile(buildInfoOutputPath, "utf-8"),
          );
          buildInfoOutputCache.set(buildInfoId, buildInfoOutput);
        }

        const directoryToSaveTo = dirname(fileName);
        const storageLayout = (
          buildInfoOutput.output.contracts![json.sourceName][
            json.contractName
          ] as any
        ).storageLayout as StorageLayout;

        const fileToSaveTo = join(
          directoryToSaveTo,
          json.contractName + ".storageLayout.json",
        );
        await writeFile(fileToSaveTo, JSON.stringify(storageLayout, null, 2));
      }
    },
  };
  return handlers;
};
