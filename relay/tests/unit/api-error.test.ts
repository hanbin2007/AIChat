import { describe, expect, it } from "vitest";
import { ApiError, errorResponse, jsonResponse } from "@/lib/api/error";

describe("ApiError + response helpers", () => {
  it("ApiError carries status + message", () => {
    const err = new ApiError(418, "I'm a teapot");
    expect(err).toBeInstanceOf(Error);
    expect(err.status).toBe(418);
    expect(err.message).toBe("I'm a teapot");
  });

  it("errorResponse wraps the message in a JSON envelope", async () => {
    const res = errorResponse(403, "nope");
    expect(res.status).toBe(403);
    expect(res.headers.get("Content-Type")).toContain("application/json");
    expect(await res.json()).toEqual({ message: "nope" });
  });

  it("jsonResponse echoes the payload as JSON", async () => {
    const res = jsonResponse(201, { ok: true, n: 42 });
    expect(res.status).toBe(201);
    expect(await res.json()).toEqual({ ok: true, n: 42 });
  });
});
