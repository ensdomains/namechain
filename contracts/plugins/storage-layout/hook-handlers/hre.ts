import { readFile } from "fs/promises";
import type { HardhatRuntimeEnvironmentHooks } from "hardhat/types/hooks";

import type { StorageLayout } from "../types.ts";

export default async (): Promise<Partial<HardhatRuntimeEnvironmentHooks>> => {
  const handlers: Partial<HardhatRuntimeEnvironmentHooks> = {
    created: async (_context, hre): Promise<void> => {
      const storageLayoutCache = new Map<string, StorageLayout>();
      Object.assign(hre.artifacts, {
        getStorageLayout: async (
          contractName: string,
        ): Promise<StorageLayout> => {
          const artifactPath =
            await hre.artifacts.getArtifactPath(contractName);
          const storageLayoutPath = artifactPath.replace(
            /\.json$/,
            ".storageLayout-json", // prevent hardhat-deploy:generateTypes() from picking this up as an artifact
          );

          if (storageLayoutCache.has(storageLayoutPath))
            return storageLayoutCache.get(storageLayoutPath)!;

          const storageLayout = JSON.parse(
            await readFile(storageLayoutPath, "utf-8"),
          ) as StorageLayout;
          storageLayoutCache.set(storageLayoutPath, storageLayout);
          return storageLayout;
        },
      });
    },
  };

  return handlers;
};
