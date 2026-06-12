"use client";

import { alpha, createTheme } from "@mui/material/styles";

const cardBorderLight = "1px solid rgba(16, 42, 67, 0.08)";
const cardBorderDark = "1px solid rgba(255, 255, 255, 0.08)";
const cardShadowLight = "0 24px 48px rgba(15, 23, 42, 0.05)";
const cardShadowDark = "0 24px 48px rgba(0, 0, 0, 0.40)";

export const theme = createTheme({
  cssVariables: {
    colorSchemeSelector: "class",
  },
  colorSchemes: {
    light: {
      palette: {
        primary: { main: "#4F6AF0", dark: "#2E48C7", light: "#A8B5FF" },
        secondary: { main: "#2563eb" },
        background: { default: "#eef3f9", paper: "#ffffff" },
        success: { main: "#2e7d32" },
        warning: { main: "#c77700" },
        error: { main: "#b3261e" },
        info: { main: "#3B6EE6" },
        text: { primary: "#102a43", secondary: "#52667a" },
        divider: "rgba(16, 42, 67, 0.08)",
      },
    },
    dark: {
      palette: {
        primary: {
          main: "#A8B5FF",
          dark: "#4F6AF0",
          light: "#D4D9FF",
          contrastText: "#0B1530",
        },
        secondary: { main: "#7AA0FF" },
        background: { default: "#0f1218", paper: "#1a1f2a" },
        success: { main: "#7CCB80" },
        warning: { main: "#E8B872" },
        error: { main: "#FFB4AB" },
        info: { main: "#A8C6FF" },
        text: { primary: "#e6e9ef", secondary: "#9ba3b3" },
        divider: "rgba(255, 255, 255, 0.08)",
      },
    },
  },
  shape: { borderRadius: 8 },
  typography: {
    fontFamily:
      '"PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC", system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
    h1: { fontWeight: 700, letterSpacing: 0 },
    h2: { fontWeight: 700, letterSpacing: 0 },
    h3: { fontWeight: 700, letterSpacing: 0 },
    h4: { fontWeight: 700 },
    h5: { fontWeight: 700 },
    h6: { fontWeight: 700 },
    button: { textTransform: "none", fontWeight: 600 },
  },
  components: {
    MuiCssBaseline: {
      styleOverrides: (themeParam) => ({
        html: { height: "100%" },
        body: {
          minHeight: "100%",
          background: `radial-gradient(circle at top left, ${alpha(
            themeParam.palette.primary.light,
            0.15,
          )}, transparent 30%), linear-gradient(180deg, #f7f9fc 0%, #eef3f9 100%)`,
          backgroundAttachment: "fixed",
          ...themeParam.applyStyles("dark", {
            background: `radial-gradient(circle at top left, ${alpha(
              themeParam.palette.primary.main,
              0.1,
            )}, transparent 30%), linear-gradient(180deg, #131722 0%, #0f1218 100%)`,
          }),
          [themeParam.breakpoints.down("sm")]: {
            backgroundAttachment: "scroll",
          },
        },
      }),
    },
    MuiPaper: {
      defaultProps: { elevation: 0 },
      styleOverrides: { root: { backgroundImage: "none" } },
    },
    MuiCard: {
      styleOverrides: {
        root: ({ theme }) => ({
          border: cardBorderLight,
          boxShadow: cardShadowLight,
          ...theme.applyStyles("dark", {
            border: cardBorderDark,
            boxShadow: cardShadowDark,
          }),
        }),
      },
    },
    MuiButton: {
      defaultProps: { disableElevation: true },
      styleOverrides: { root: { borderRadius: 8 } },
    },
    MuiChip: { styleOverrides: { root: { borderRadius: 8 } } },
    MuiDrawer: {
      styleOverrides: {
        paper: ({ theme }) => ({
          borderRight: cardBorderLight,
          backgroundColor: "rgba(255, 255, 255, 0.92)",
          backdropFilter: "blur(18px)",
          ...theme.applyStyles("dark", {
            borderRight: cardBorderDark,
            backgroundColor: "rgba(20, 25, 36, 0.92)",
          }),
        }),
      },
    },
    MuiAppBar: {
      defaultProps: { color: "default", elevation: 0 },
      styleOverrides: {
        root: ({ theme }) => ({
          borderBottom: cardBorderLight,
          backgroundColor: theme.palette.background.paper,
          ...theme.applyStyles("dark", { borderBottom: cardBorderDark }),
        }),
      },
    },
    MuiDialog: { styleOverrides: { paper: { borderRadius: 16 } } },
    MuiTableCell: { styleOverrides: { head: { fontWeight: 700 } } },
    MuiTextField: { defaultProps: { fullWidth: true, variant: "outlined" } },
    MuiTab: {
      styleOverrides: {
        root: { textTransform: "none", fontWeight: 600, minHeight: 48 },
      },
    },
  },
});
