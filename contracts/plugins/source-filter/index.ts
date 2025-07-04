import { overrideTask } from "hardhat/config";
import type { HardhatPlugin } from "hardhat/types/plugins";

declare module "hardhat/types/config" {
  interface HardhatUserConfig {
    sourceFilter?: (path: string) => boolean;
  }
}

const HardhatSourceFilterPlugin: HardhatPlugin = {
  id: "hardhat-source-filter",
  tasks: [
    overrideTask("compile")
      .setAction(import.meta.resolve("./task.ts"))
      .build(),
  ],
};

export default HardhatSourceFilterPlugin;
