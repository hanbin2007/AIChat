import { redirect } from "next/navigation";
import { readSession } from "@/lib/auth/session";
import { settingsStore } from "@/lib/store/settings-store";
import { AppShell } from "@/components/shell/app-shell";
import { PageMetaProvider } from "@/components/shell/page-meta";

export const dynamic = "force-dynamic";

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const setup = await settingsStore().isSetupComplete();
  if (!setup) redirect("/setup");
  const session = await readSession();
  if (!session) redirect("/login");
  return (
    <PageMetaProvider>
      <AppShell>{children}</AppShell>
    </PageMetaProvider>
  );
}
