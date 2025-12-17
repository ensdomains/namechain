import { setupCrossChainEnvironment } from "./setup.js";

while (true) {
  const { shutdown } = await setupCrossChainEnvironment({
    quiet: false,
  });
  await shutdown();
}
