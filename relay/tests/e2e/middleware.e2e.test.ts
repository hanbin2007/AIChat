import { describe, expect, it } from "vitest";

const baseUrl = (): string => {
  const u = process.env.E2E_BASE_URL;
  if (!u) throw new Error("E2E_BASE_URL not set");
  return u;
};

describe("E2E middleware on /api/v1/*", () => {
  it("answers OPTIONS preflight with 204 + CORS headers", async () => {
    const res = await fetch(`${baseUrl()}/api/v1/billing/catalog`, {
      method: "OPTIONS",
      headers: { Origin: "https://client.example", "Access-Control-Request-Method": "GET" },
    });
    expect(res.status).toBe(204);
    expect(res.headers.get("access-control-allow-origin")).toBe("https://client.example");
    expect(res.headers.get("access-control-allow-methods")).toMatch(/GET/);
    expect(res.headers.get("access-control-allow-headers")).toMatch(/Authorization/);
  });

  it("attaches CORS + x-relay-request-id headers on real GETs", async () => {
    const res = await fetch(`${baseUrl()}/api/v1/billing/catalog`, {
      headers: {
        Authorization: "Bearer e2e-bearer-token",
        Origin: "https://client.example",
      },
    });
    expect(res.headers.get("access-control-allow-origin")).toBe("https://client.example");
    expect(res.headers.get("x-relay-request-id")).toBeTruthy();
  });

  it("preserves a caller-supplied request id", async () => {
    const id = "req_e2etest_12345";
    const res = await fetch(`${baseUrl()}/api/v1/billing/catalog`, {
      headers: {
        Authorization: "Bearer e2e-bearer-token",
        "x-relay-request-id": id,
      },
    });
    expect(res.headers.get("x-relay-request-id")).toBe(id);
  });

  it("does not attach CORS headers outside /api/v1/", async () => {
    const res = await fetch(`${baseUrl()}/api/health`);
    expect(res.headers.get("access-control-allow-origin")).toBeNull();
  });
});
