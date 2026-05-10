import { redirect } from "next/navigation";
import { settingsStore } from "@/lib/store/settings-store";
import SetupForm from "./setup-form";

export const dynamic = "force-dynamic";

export default async function SetupPage() {
  if (await settingsStore().isSetupComplete()) {
    redirect("/login");
  }
  return <SetupForm />;
}
