import { beforeEach, describe, expect, it } from "vitest";
import { GET } from "@/app/api/health/route";
import { resetState } from "../helpers";

describe("GET /api/health", () => {
  beforeEach(resetState);

  it("returns 200 with diagnostics", async () => {
    const res = await GET();
    expect(res.status).toBe(200);
    const body = (await res.json()) as { ok: boolean; diagnostics: Record<string, unknown> };
    expect(body.ok).toBe(true);
    expect(body.diagnostics.geminiConfigured).toBe(true);
    expect(body.diagnostics.bearerConfigured).toBe(true);
  });
});
