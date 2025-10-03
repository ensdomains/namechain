import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    reporters: ["verbose"],
    include: ["test/integration/**/*.test.ts"],
    setupFiles: ["test/integration/vitest-setup.ts"],
  },
});
