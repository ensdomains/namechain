import { overrideTask } from "hardhat/config";
import type { HardhatPlugin } from "hardhat/types/plugins";

declare module "hardhat/types/config" {
  interface HardhatUserConfig {
    shouldIgnoreWarnings?: (path: string, error: string) => boolean;
  }
}

const plugin: HardhatPlugin = {
  id: "hardhat-ignore-warnings",
  tasks: [
    overrideTask("compile")
      .setAction(import.meta.resolve("./task.ts"))
      .build(),
  ],
};

export default plugin;
