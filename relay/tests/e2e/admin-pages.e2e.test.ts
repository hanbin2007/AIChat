import { beforeAll, describe, expect, it } from "vitest";

const baseUrl = (): string => {
  const u = process.env.E2E_BASE_URL;
  if (!u) throw new Error("E2E_BASE_URL not set");
  return u;
};

let cookie = "";

beforeAll(async () => {
  const res = await fetch(`${baseUrl()}/api/admin/login`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ username: "admin", password: "e2etestpassword" }),
  });
  if (!res.ok) throw new Error(`admin login failed: ${res.status}`);
  cookie = (res.headers.get("set-cookie") ?? "").split(";")[0];
  if (!cookie) throw new Error("login did not return a cookie");
});

const adminPages = [
  "/dashboard",
  "/requests",
  "/billing",
  "/accounts",
  "/observability",
  "/models",
  "/settings",
  "/playground",
  "/docs",
  "/about",
];

describe("E2E admin pages render under a valid session", () => {
  it.each(adminPages)("renders %s as HTML", async (path) => {
    const res = await fetch(`${baseUrl()}${path}`, { headers: { cookie } });
    expect(res.status, `${path} status`).toBe(200);
    const ct = res.headers.get("content-type") ?? "";
    expect(ct).toMatch(/text\/html/);
    const html = await res.text();
    expect(html.length, `${path} body length`).toBeGreaterThan(500);
    expect(html).toMatch(/<html/i);
  });

  it("redirects unauthenticated /dashboard requests to /login", async () => {
    const res = await fetch(`${baseUrl()}/dashboard`, { redirect: "manual" });
    expect([302, 307, 308]).toContain(res.status);
    const loc = res.headers.get("location") ?? "";
    expect(loc).toMatch(/\/login/);
  });
});
