import { overrideTask } from "hardhat/config";
import type { HardhatPlugin } from "hardhat/types/plugins";

declare module "hardhat/types/config" {
  interface HardhatUserConfig {
    shouldIgnoreWarnings?: (path: string, error: string) => boolean;
  }
}

const plugin: HardhatPlugin = {
  id: "hardhat-ignore-warnings",
  // 20250828: hardhat treats these separately even though they alias
  tasks: ["build", "compile"].map((action) =>
    overrideTask(action)
      .setAction(() => import("./task.ts"))
      .build(),
  ),
};

export default plugin;
