import type { Metadata } from "next";
import "./globals.css";
import { SnackbarProvider } from "@/components/m3/snackbar";

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
          href="https://fonts.googleapis.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@24,400,0,0&family=Roboto+Flex:opsz,wght@8..144,300..700&family=Roboto+Mono:wght@400;500&family=Noto+Sans+SC:wght@400;500;700&display=swap"
        />
        <script
          // Read stored theme before hydration to avoid flash.
          dangerouslySetInnerHTML={{
            __html: `(function(){try{var t=localStorage.getItem("relay_theme");var pref=t||(matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light');if(pref==='dark')document.documentElement.classList.add('dark');}catch(e){}})();`,
          }}
        />
      </head>
      <body className="min-h-screen bg-surface text-on-surface">
        <SnackbarProvider>{children}</SnackbarProvider>
      </body>
    </html>
  );
}
