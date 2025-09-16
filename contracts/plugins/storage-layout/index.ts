import type { HardhatPlugin } from "hardhat/types/plugins";

import "./type-extensions.ts";

const HardhatStorageLayoutPlugin: HardhatPlugin = {
  id: "hardhat-storage-layout",
  hookHandlers: {
    solidity: () => import("./hook-handlers/compile.ts"),
    hre: () => import("./hook-handlers/hre.ts"),
  },
};

export default HardhatStorageLayoutPlugin;
