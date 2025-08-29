import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    reporters: ["verbose"],
    include: ["test/**/*.test.ts"],
    setupFiles: ["test/vitest-setup.ts"], // explained below
    globalSetup: ["test/vitest-setup.ts"], // see: setup.ts
  },
});
