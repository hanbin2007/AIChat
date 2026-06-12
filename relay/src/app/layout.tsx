import type { Metadata } from "next";
import { Noto_Sans_SC, IBM_Plex_Mono } from "next/font/google";
import InitColorSchemeScript from "@mui/material/InitColorSchemeScript";
import "./globals.css";
import "katex/dist/katex.min.css";
import { Providers } from "./providers";

const body = Noto_Sans_SC({
  subsets: ["latin"],
  weight: ["400", "500", "700"],
  variable: "--font-body",
  display: "swap",
});

const mono = IBM_Plex_Mono({
  subsets: ["latin"],
  weight: ["400", "500", "700"],
  variable: "--font-mono",
  display: "swap",
});

export const metadata: Metadata = {
  title: "AIChat Relay 控制台",
  description: "AIChat 中继网关管理控制台",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html
      lang="zh-Hans"
      className={`${body.variable} ${mono.variable}`}
      suppressHydrationWarning
    >
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
