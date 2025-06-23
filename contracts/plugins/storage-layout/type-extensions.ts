import "hardhat/types/artifacts";

import type { StorageLayout } from "./types.ts";

declare module "hardhat/types/artifacts" {
  interface ArtifactManager {
    getStorageLayout: (contractName: string) => Promise<StorageLayout>;
  }
}
