import { describe, expect, it } from "vitest";

const baseUrl = (): string => {
  const u = process.env.E2E_BASE_URL;
  if (!u) throw new Error("E2E_BASE_URL not set — globalSetup did not run?");
  return u;
};

describe("E2E /api/health", () => {
  it("returns 200 with a JSON body", async () => {
    const res = await fetch(`${baseUrl()}/api/health`);
    expect(res.status).toBe(200);
    const ct = res.headers.get("content-type") ?? "";
    expect(ct).toMatch(/application\/json/);
    const body = await res.json();
    expect(body).toBeTypeOf("object");
  });
});
