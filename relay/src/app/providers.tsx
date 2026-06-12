"use client";

import { AppRouterCacheProvider } from "@mui/material-nextjs/v15-appRouter";
import CssBaseline from "@mui/material/CssBaseline";
import { ThemeProvider } from "@mui/material/styles";
import { theme } from "@/theme";
import { SnackbarProvider } from "@/components/snackbar-provider";

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <AppRouterCacheProvider options={{ key: "mui" }}>
      <ThemeProvider theme={theme} defaultMode="system" modeStorageKey="relay_theme">
        <CssBaseline enableColorScheme />
        <SnackbarProvider>{children}</SnackbarProvider>
      </ThemeProvider>
    </AppRouterCacheProvider>
  );
}
