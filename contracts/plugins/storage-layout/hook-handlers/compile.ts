import { readFile, writeFile } from "fs/promises";
import type { Artifact } from "hardhat/types/artifacts";
import type { SolidityHooks } from "hardhat/types/hooks";
import type { SolidityBuildInfoOutput } from "hardhat/types/solidity";
import { dirname, join } from "path";

import type { StorageLayout } from "../types.ts";

export default async (): Promise<Partial<SolidityHooks>> => {
  const handlers: Partial<SolidityHooks> = {
    onCleanUpArtifacts: async (context, artifactFiles, next) => {
      const buildInfoOutputCache = new Map<
        string,
        { path: string; output: SolidityBuildInfoOutput }
      >();
      for (const fileName of artifactFiles) {
        const file = await readFile(fileName, "utf-8");
        const json = JSON.parse(file) as Artifact;
        const buildInfoId = json.buildInfoId;
        if (!buildInfoId) continue;
        let buildInfoOutput: SolidityBuildInfoOutput;
        if (buildInfoOutputCache.has(buildInfoId)) {
          buildInfoOutput = buildInfoOutputCache.get(buildInfoId)!.output;
        } else {
          const buildInfoOutputPath =
            (await context.artifacts.getBuildInfoOutputPath(buildInfoId))!;
          buildInfoOutput = JSON.parse(
            await readFile(buildInfoOutputPath, "utf-8"),
          );
          buildInfoOutputCache.set(buildInfoId, {
            path: buildInfoOutputPath,
            output: buildInfoOutput,
          });
        }

        const directoryToSaveTo = dirname(fileName);
        const storageLayout = (
          buildInfoOutput.output.contracts![json.inputSourceName!][
            json.contractName
          ] as any
        ).storageLayout as StorageLayout;

        const fileToSaveTo = join(
          directoryToSaveTo,
          json.contractName + ".storageLayout.json",
        );

        if (storageLayout)
          await writeFile(fileToSaveTo, JSON.stringify(storageLayout, null, 2));

        const { ast } = buildInfoOutput.output.sources![json.inputSourceName!];
        // legacy solidity version
        if (!ast) {
          // add ast to buildInfoOutput and rewrite file
          const buildInfoOutputPath =
            buildInfoOutputCache.get(buildInfoId)!.path;
          const updatedBuildInfo = {
            ...buildInfoOutput,
            output: {
              ...buildInfoOutput.output,
              sources: {
                ...buildInfoOutput.output.sources,
                [json.inputSourceName!]: {
                  ...buildInfoOutput.output.sources![json.inputSourceName!],
                  ast: {},
                },
              },
            },
          };
          await writeFile(
            buildInfoOutputPath,
            JSON.stringify(updatedBuildInfo),
          );
        }
      }
      return next(context, artifactFiles);
    },
  };
  return handlers;
};
