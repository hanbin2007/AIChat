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
