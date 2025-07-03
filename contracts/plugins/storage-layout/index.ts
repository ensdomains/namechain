import type { HardhatPlugin } from "hardhat/types/plugins";

import "./type-extensions.ts";

const HardhatStorageLayoutPlugin: HardhatPlugin = {
  id: "hardhat-storage-layout",
  hookHandlers: {
    solidity: import.meta.resolve("./hook-handlers/compile.ts"),
    hre: import.meta.resolve("./hook-handlers/hre.ts"),
  },
  dependencies: [],
};

export default HardhatStorageLayoutPlugin;
