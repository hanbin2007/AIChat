"use client";
import * as React from "react";
import Link from "next/link";
import { Card, Icon } from "@/components/m3";
import { cn } from "@/lib/cn";

export interface ChecklistItem {
  id: string;
  label: string;
  description: string;
  done: boolean;
  href?: string;
}

export function LaunchChecklist({ items }: { items: ChecklistItem[] }) {
  const allDone = items.every((i) => i.done);
  return (
    <Card variant="filled" className="p-5">
      <div className="mb-4 flex items-center gap-3">
        <span
          className={cn(
            "flex h-10 w-10 items-center justify-center rounded-full",
            allDone ? "bg-secondary-container text-on-secondary-container" : "bg-tertiary-container text-on-tertiary-container",
          )}
        >
          <Icon name={allDone ? "check_circle" : "flag"} size={22} filled />
        </span>
        <div>
          <div className="text-m3-title-m font-medium">
            {allDone ? "Ready to serve" : "启动清单"}
          </div>
          <div className="text-m3-body-s text-on-surface-variant">
            {allDone ? "所有关键配置已就绪" : `完成 ${items.filter((i) => i.done).length}/${items.length} 项即可正式上线`}
          </div>
        </div>
      </div>
      <ol className="relative space-y-2">
        {items.map((item, i) => (
          <li key={item.id}>
            <Link
              href={item.href ?? "#"}
              className="state-layer flex items-start gap-3 rounded-m3-sm px-2 py-2"
            >
              <span
                className={cn(
                  "mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-m3-label-m",
                  item.done
                    ? "bg-secondary-container text-on-secondary-container"
                    : "bg-surface-container-highest text-on-surface-variant",
                )}
              >
                {item.done ? <Icon name="check" size={14} /> : i + 1}
              </span>
              <div className="flex-1">
                <div className="text-m3-title-s">{item.label}</div>
                <div className="text-m3-body-s text-on-surface-variant">{item.description}</div>
              </div>
              {item.href && !item.done && (
                <Icon name="arrow_forward" size={18} className="text-on-surface-variant" />
              )}
            </Link>
          </li>
        ))}
      </ol>
    </Card>
  );
}
