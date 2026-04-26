import { redirect } from "next/navigation";
import { readSession } from "@/lib/auth/session";
import { settingsStore } from "@/lib/store/settings-store";

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const setup = await settingsStore().isSetupComplete();
  if (!setup) redirect("/setup");
  const session = await readSession();
  if (!session) redirect("/login");
  return <>{children}</>;
}
