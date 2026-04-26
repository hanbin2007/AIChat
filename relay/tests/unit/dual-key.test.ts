import { describe, expect, it } from "vitest";
import { pick } from "@/lib/gemini/dual-key";

describe("pick (snake/camel dual-key codec)", () => {
  it("returns the first matching key", () => {
    expect(pick({ a: 1, b: 2 }, "a", "b")).toBe(1);
    expect(pick({ b: 2 }, "a", "b")).toBe(2);
  });

  it("returns undefined when nothing matches", () => {
    expect(pick({ a: 1 }, "b", "c")).toBeUndefined();
    expect(pick(undefined, "a")).toBeUndefined();
  });

  it("skips undefined properties even if the key exists", () => {
    expect(pick({ a: undefined, b: 7 }, "a", "b")).toBe(7);
  });

  it("handles snake_case and camelCase aliases transparently", () => {
    expect(pick({ system_prompt: "hello" }, "systemPrompt", "system_prompt")).toBe("hello");
    expect(pick({ systemPrompt: "hi" }, "systemPrompt", "system_prompt")).toBe("hi");
  });
});
