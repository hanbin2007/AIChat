import type { Metadata } from "next";
import InitColorSchemeScript from "@mui/material/InitColorSchemeScript";
import "./globals.css";
import { Providers } from "./providers";

export const metadata: Metadata = {
  title: "AIChat Relay 控制台",
  description: "AIChat 中继网关管理控制台",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="zh-Hans" suppressHydrationWarning>
      <body>
        <InitColorSchemeScript
          attribute="class"
          modeStorageKey="relay_theme"
          defaultMode="system"
        />
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
