import { defineConfig } from "vitest/config";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));

/**
 * E2E config — boots a real `next start` once via globalSetup, then runs
 * tests under tests/e2e/**.e2e.test.ts against it via HTTP.
 *
 * Kept separate from the default vitest run so unit/integration tests stay
 * fast and don't require a build artifact.
 */
export default defineConfig({
  esbuild: { jsx: "automatic" },
  resolve: {
    alias: { "@": path.resolve(root, "src") },
  },
  test: {
    environment: "node",
    globals: false,
    include: ["tests/e2e/**/*.e2e.test.ts"],
    globalSetup: ["tests/e2e/global-setup.ts"],
    testTimeout: 30_000,
    hookTimeout: 60_000,
    pool: "forks",
    poolOptions: { forks: { singleFork: true } },
  },
});
