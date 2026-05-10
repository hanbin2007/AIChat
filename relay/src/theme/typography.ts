import type { TypographyVariantsOptions } from "@mui/material/styles";

const fontFamily = [
  '"Roboto Flex"',
  '"Noto Sans SC"',
  "system-ui",
  "-apple-system",
  "sans-serif",
].join(", ");

export const typography: TypographyVariantsOptions = {
  fontFamily,
  htmlFontSize: 16,
  fontSize: 14,
  fontWeightLight: 300,
  fontWeightRegular: 400,
  fontWeightMedium: 500,
  fontWeightBold: 700,
  h1: { fontSize: "2.25rem", fontWeight: 500, lineHeight: 1.2, letterSpacing: "-0.01em" },
  h2: { fontSize: "1.875rem", fontWeight: 500, lineHeight: 1.25 },
  h3: { fontSize: "1.5rem", fontWeight: 500, lineHeight: 1.3 },
  h4: { fontSize: "1.25rem", fontWeight: 500, lineHeight: 1.35 },
  h5: { fontSize: "1.125rem", fontWeight: 500, lineHeight: 1.4 },
  h6: { fontSize: "1rem", fontWeight: 500, lineHeight: 1.5 },
  subtitle1: { fontSize: "1rem", fontWeight: 500, lineHeight: 1.5 },
  subtitle2: { fontSize: "0.875rem", fontWeight: 500, lineHeight: 1.5 },
  body1: { fontSize: "0.9375rem", lineHeight: 1.55 },
  body2: { fontSize: "0.875rem", lineHeight: 1.5 },
  button: { fontSize: "0.875rem", fontWeight: 500, letterSpacing: "0.02em", textTransform: "none" },
  caption: { fontSize: "0.75rem", lineHeight: 1.4 },
  overline: { fontSize: "0.6875rem", letterSpacing: "0.08em", textTransform: "uppercase", fontWeight: 500 },
};
