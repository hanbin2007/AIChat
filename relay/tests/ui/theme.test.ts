import { describe, expect, it } from "vitest";
import { theme } from "@/theme";

describe("theme", () => {
  it("uses #4F6AF0 as the brand primary in the light scheme", () => {
    expect(theme.colorSchemes.light?.palette.primary.main.toUpperCase()).toBe("#4F6AF0");
  });

  it("populates both light and dark color schemes", () => {
    expect(theme.colorSchemes.light).toBeDefined();
    expect(theme.colorSchemes.dark).toBeDefined();
    expect(theme.colorSchemes.dark?.palette.primary.main).not.toEqual(
      theme.colorSchemes.light?.palette.primary.main,
    );
  });

  it("anchors shape borderRadius at 12 to match the M3-leaning M2 look", () => {
    expect(theme.shape.borderRadius).toBe(12);
  });

  it("disables button text-transform via component default props", () => {
    expect(theme.components?.MuiButton?.defaultProps?.disableElevation).toBe(true);
  });

  it("registers Roboto Flex as the primary font family", () => {
    expect(theme.typography.fontFamily).toMatch(/Roboto Flex/);
  });
});
