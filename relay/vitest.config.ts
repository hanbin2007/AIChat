import { defineConfig } from "vitest/config";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  esbuild: {
    jsx: "automatic",
  },
  resolve: {
    alias: {
      "@": path.resolve(root, "src"),
    },
  },
  test: {
    environment: "node",
    globals: false,
    setupFiles: ["./tests/setup.ts"],
    testTimeout: 15_000,
    hookTimeout: 10_000,
    include: ["tests/**/*.test.ts", "tests/**/*.test.tsx"],
    exclude: ["**/node_modules/**", "tests/e2e/**"],
    environmentMatchGlobs: [["tests/ui/**", "happy-dom"]],
    coverage: {
      provider: "v8",
      reporter: ["text", "html"],
      include: ["src/**/*.{ts,tsx}"],
      // Server-rendered page components (`page.tsx` under `src/app/`) are
      // integration surfaces that depend on the Next.js runtime; they are
      // exercised by the E2E suite (`tests/e2e/**/*.e2e.test.ts`) which
      // boots a real `next start` and renders each page over HTTP. They
      // are therefore excluded from the vitest coverage scope, which
      // measures only in-process unit/integration code.
      exclude: [
        "src/**/*.d.ts",
        "src/lib/gemini/models.ts",
        "src/app/**/layout.tsx",
        "src/app/**/loading.tsx",
        "src/app/**/error.tsx",
        "src/app/**/providers.tsx",
        "src/app/page.tsx",
        "src/app/(admin)/**/page.tsx",
        "src/app/login/page.tsx",
        "src/app/setup/setup-form.tsx",
        "src/app/globals.css",
      ],
      thresholds: {
        lines: 70,
        statements: 70,
        functions: 70,
        branches: 70,
      },
    },
  },
});
