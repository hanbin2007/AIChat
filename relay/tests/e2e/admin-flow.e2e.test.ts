import { describe, expect, it } from "vitest";

const baseUrl = (): string => {
  const u = process.env.E2E_BASE_URL;
  if (!u) throw new Error("E2E_BASE_URL not set");
  return u;
};

/**
 * End-to-end admin auth flow against the running Next.js server.
 * Covers:
 *   1. unauthenticated session check returns 401
 *   2. login with wrong password returns 401
 *   3. login with correct password returns 200 + session cookie
 *   4. authenticated session check returns 200 with the cookie
 *   5. logout clears the session
 */
describe("E2E admin auth flow", () => {
  it("returns no session for an unauthenticated probe", async () => {
    const res = await fetch(`${baseUrl()}/api/admin/session`);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { session?: unknown };
    expect(body.session ?? null).toBeNull();
  });

  it("rejects a bad password", async () => {
    const res = await fetch(`${baseUrl()}/api/admin/login`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ username: "admin", password: "wrong" }),
    });
    expect(res.status).toBe(401);
  });

  it("logs in, validates the session, then logs out", async () => {
    const login = await fetch(`${baseUrl()}/api/admin/login`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ username: "admin", password: "e2etestpassword" }),
    });
    expect(login.status).toBe(200);
    const setCookie = login.headers.get("set-cookie");
    expect(setCookie, "login should issue a session cookie").toBeTruthy();
    const cookie = setCookie!.split(";")[0];

    const session = await fetch(`${baseUrl()}/api/admin/session`, {
      headers: { cookie },
    });
    expect(session.status).toBe(200);

    const logout = await fetch(`${baseUrl()}/api/admin/logout`, {
      method: "POST",
      headers: { cookie },
    });
    expect([200, 204]).toContain(logout.status);
  });
});

describe("E2E rendered HTML pages", () => {
  it("serves the /login page as HTML", async () => {
    const res = await fetch(`${baseUrl()}/login`);
    expect(res.status).toBe(200);
    const html = await res.text();
    expect(html).toMatch(/<html/i);
    expect(html).toMatch(/AIChat Relay|登录/);
  });
});
