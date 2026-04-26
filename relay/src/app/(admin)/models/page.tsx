"use client";
import * as React from "react";
import Link from "next/link";
import { AdminShell } from "@/components/admin-shell";
import { Card, CardContent, CardHeader, CardTitle, Badge, Icon } from "@/components/m3";
import { DEFAULT_MODELS } from "@/lib/gemini/models";

const CAPABILITY_ICONS: Record<string, { icon: string; label: string }> = {
  thinking: { icon: "psychology", label: "Thinking" },
  search: { icon: "travel_explore", label: "Search" },
  codeExecution: { icon: "code", label: "Code" },
  audio: { icon: "headphones", label: "Audio" },
  vision: { icon: "image", label: "Vision" },
};

export default function ModelsPage() {
  return (
    <AdminShell title="Models" breadcrumb={["Relay"]}>
      <div className="p-6">
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {DEFAULT_MODELS.map((m) => (
            <Card key={m.id} variant="outlined" className="p-5">
              <CardTitle>{m.displayName}</CardTitle>
              <div className="mt-1 font-mono text-m3-label-m text-on-surface-variant">{m.id}</div>
              <div className="mt-1 text-m3-body-s text-on-surface-variant">family: {m.family}</div>
              <div className="mt-4 flex flex-wrap gap-2">
                {Object.entries(m.capabilities).map(([k, enabled]) =>
                  enabled ? (
                    <span
                      key={k}
                      className="inline-flex items-center gap-1 rounded-full bg-surface-container-highest px-3 py-1 text-m3-label-s"
                    >
                      <Icon name={CAPABILITY_ICONS[k].icon} size={16} />
                      {CAPABILITY_ICONS[k].label}
                    </span>
                  ) : null,
                )}
              </div>
              <div className="mt-4">
                <div className="text-m3-label-m text-on-surface-variant">支持的思考强度</div>
                <div className="mt-1 flex gap-2">
                  {m.supportedIntensities.map((i) => <Badge key={i}>{i}</Badge>)}
                </div>
              </div>
              <div className="mt-4 border-t border-outline-variant pt-3">
                <Link href="/billing" className="text-m3-label-l text-primary hover:underline">
                  在 Billing Studio 中编辑计价 →
                </Link>
              </div>
            </Card>
          ))}
        </div>
      </div>
    </AdminShell>
  );
}
