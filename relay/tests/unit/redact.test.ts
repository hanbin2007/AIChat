import { describe, expect, it } from "vitest";
import { mask, redactSensitive, stripAuthHeader } from "@/lib/observability/redact";

describe("redaction helpers", () => {
  it("mask keeps the last 6 characters", () => {
    expect(mask("super-secret-token")).toBe("••••••-token");
    expect(mask("short")).toBe("••••••");
    expect(mask(undefined)).toBe("");
  });

  it("stripAuthHeader masks Bearer tokens while preserving other headers", () => {
    const out = stripAuthHeader({
      Authorization: "Bearer rk_abcdef1234567890",
      "X-Other": "visible",
    });
    expect(out["X-Other"]).toBe("visible");
    expect(out.Authorization).toMatch(/^Bearer •••••/);
    expect(out.Authorization).not.toContain("rk_abcdef1234567890");
  });

  it("redactSensitive replaces env-configured bearer + gemini tokens", () => {
    const original = `Authorization: Bearer test-bearer-token (key=test-gemini-key)`;
    const redacted = redactSensitive(original);
    expect(redacted).not.toContain("test-bearer-token");
    expect(redacted).not.toContain("test-gemini-key");
  });

  it("applies extra regex patterns", () => {
    const redacted = redactSensitive("call 415-555-1212 now", [/\d{3}-\d{3}-\d{4}/g]);
    expect(redacted).not.toContain("415-555-1212");
  });
});
