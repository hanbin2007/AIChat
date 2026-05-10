import type { Metadata } from "next";
import "./globals.css";
import InitColorSchemeScript from "@mui/material/InitColorSchemeScript";
import { Providers } from "./providers";
import { SnackbarProvider } from "@/components/snackbar-provider";

export const metadata: Metadata = {
  title: "AIChat Relay",
  description: "Enterprise relay gateway for AIChat clients",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="zh-Hans" suppressHydrationWarning>
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link
          rel="stylesheet"
          href="https://fonts.googleapis.com/css2?family=Roboto+Flex:opsz,wght@8..144,300..700&family=Roboto+Mono:wght@400;500&family=Noto+Sans+SC:wght@400;500;700&display=swap"
        />
      </head>
      <body>
        <InitColorSchemeScript attribute="data-mui-color-scheme" modeStorageKey="relay_theme" />
        <Providers>
          <SnackbarProvider>{children}</SnackbarProvider>
        </Providers>
      </body>
    </html>
  );
}
