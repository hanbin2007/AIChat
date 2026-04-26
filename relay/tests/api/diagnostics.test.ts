import { beforeEach, describe, expect, it } from "vitest";
import { GET as bundle } from "@/app/api/admin/diagnostics/bundle/route";
import { POST as login } from "@/app/api/admin/login/route";
import { auditLog } from "@/lib/store/audit-log";
import { makeRequest, resetState } from "../helpers";

describe("GET /api/admin/diagnostics/bundle", () => {
  beforeEach(async () => {
    await resetState();
    await login(
      makeRequest({
        url: "http://t/login",
        method: "POST",
        body: { username: "admin", password: "testpassword" },
      }),
    );
  });

  it("returns a redacted JSON bundle with attachment headers", async () => {
    const res = await bundle();
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Disposition")).toMatch(/relay-diagnostics-/);
    const data = (await res.json()) as {
      version: string;
      diagnostics: Record<string, unknown>;
      settings: { adminUsers: { passwordHash: string }[] };
      billing: { activationCodes: { code: string }[] };
    };
    expect(data.version).toBeDefined();
    if (data.settings.adminUsers.length) {
      expect(data.settings.adminUsers[0].passwordHash).toBe("[redacted]");
    }
    // Activation codes are masked.
    for (const c of data.billing.activationCodes) {
      expect(c.code.startsWith("••••••")).toBe(true);
    }
  });

  it("does not leak Gemini API key, bearer token, or session secret", async () => {
    const res = await bundle();
    const text = await res.text();
    expect(text).not.toContain(process.env.GEMINI_API_KEY!);
    expect(text).not.toContain(process.env.RELAY_BEARER_TOKEN!);
    expect(text).not.toContain(process.env.RELAY_SESSION_SECRET!);
  });

  it("logs an audit entry for the download", async () => {
    await bundle();
    const entries = await auditLog().list();
    expect(entries.some((e) => e.action === "diagnostics.bundle.download")).toBe(true);
  });
});
