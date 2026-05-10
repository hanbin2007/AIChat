/**
 * E2E server fixture — boots a real `next start` process on a free port with
 * an isolated data dir, waits for readiness, and exposes a baseUrl for tests.
 *
 * Used by tests/e2e/**.e2e.test.ts. The process is global per Vitest run so
 * boot/teardown happens once even across multiple e2e files.
 */
import { spawn, ChildProcess } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import net from "node:net";

let proc: ChildProcess | null = null;
let baseUrl = "";
let dataDir = "";

function pickPort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.unref();
    srv.on("error", reject);
    srv.listen(0, () => {
      const addr = srv.address();
      if (typeof addr === "object" && addr) {
        const p = addr.port;
        srv.close(() => resolve(p));
      } else {
        reject(new Error("could not allocate port"));
      }
    });
  });
}

async function waitForReady(url: string, timeoutMs = 30_000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  let lastErr: unknown = null;
  while (Date.now() < deadline) {
    try {
      const r = await fetch(`${url}/api/health`);
      if (r.ok) return;
    } catch (err) {
      lastErr = err;
    }
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error(`server did not become ready at ${url}: ${String(lastErr)}`);
}

export async function startServer(): Promise<{ baseUrl: string }> {
  if (proc && baseUrl) return { baseUrl };
  const port = await pickPort();
  dataDir = mkdtempSync(path.join(tmpdir(), "relay-e2e-"));
  const env: NodeJS.ProcessEnv = {
    ...process.env,
    PORT: String(port),
    HOSTNAME: "127.0.0.1",
    RELAY_DATA_DIR: dataDir,
    GEMINI_API_KEY: "e2e-gemini-key",
    RELAY_BEARER_TOKEN: "e2e-bearer-token",
    RELAY_SESSION_SECRET: "0".repeat(64),
    RELAY_ADMIN_USER: "admin",
    RELAY_ADMIN_PASSWORD: "e2etestpassword",
    RELAY_BILLING_MODE: "stub",
    RELAY_DEBUG_LOGGING: "0",
    NODE_ENV: "production",
  };
  proc = spawn("node_modules/.bin/next", ["start", "-p", String(port), "-H", "127.0.0.1"], {
    cwd: path.resolve(__dirname, "..", ".."),
    env,
    stdio: ["ignore", "pipe", "pipe"],
  });
  proc.stdout?.on("data", () => {/* swallow */});
  proc.stderr?.on("data", () => {/* swallow */});
  proc.once("exit", (code) => {
    if (code != null && code !== 0 && code !== 143) {
      // 143 = SIGTERM; only log unexpected exits
      // eslint-disable-next-line no-console
      console.error(`[e2e] next start exited unexpectedly with code ${code}`);
    }
  });
  baseUrl = `http://127.0.0.1:${port}`;
  await waitForReady(baseUrl);
  return { baseUrl };
}

export async function stopServer(): Promise<void> {
  if (proc) {
    proc.kill("SIGTERM");
    await new Promise<void>((resolve) => {
      if (!proc) return resolve();
      proc.once("exit", () => resolve());
      setTimeout(() => {
        if (proc && proc.exitCode == null) proc.kill("SIGKILL");
        resolve();
      }, 5_000);
    });
    proc = null;
  }
  if (dataDir) {
    try { rmSync(dataDir, { recursive: true, force: true }); } catch {/* ignore */}
    dataDir = "";
  }
  baseUrl = "";
}

export function getBaseUrl(): string {
  if (!baseUrl) throw new Error("e2e server not started");
  return baseUrl;
}
