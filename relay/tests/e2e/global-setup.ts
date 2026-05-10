import { startServer, stopServer, getBaseUrl } from "./server-fixture";

export async function setup(): Promise<void> {
  const { baseUrl } = await startServer();
  process.env.E2E_BASE_URL = baseUrl;
}

export async function teardown(): Promise<void> {
  await stopServer();
  delete process.env.E2E_BASE_URL;
  void getBaseUrl;
}
