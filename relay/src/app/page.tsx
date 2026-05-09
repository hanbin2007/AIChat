import { redirect } from "next/navigation";
import { readSession } from "@/lib/auth/session";
import { settingsStore } from "@/lib/store/settings-store";

export const dynamic = "force-dynamic";

export default async function RootPage() {
  const setup = await settingsStore().isSetupComplete();
  if (!setup) redirect("/setup");
  const session = await readSession();
  if (!session) redirect("/login");
  redirect("/dashboard");
}
