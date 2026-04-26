"use client";
import { Button } from "@/components/m3";

export function AboutActions() {
  return (
    <div className="flex flex-wrap gap-3">
      <Button
        variant="filled"
        icon="archive"
        onClick={() => (window.location.href = "/api/admin/diagnostics/bundle")}
      >
        下载诊断包 (JSON)
      </Button>
      <Button
        variant="outlined"
        icon="download"
        onClick={() => (window.location.href = "/api/admin/requests")}
      >
        下载 requests JSON
      </Button>
      <Button
        variant="outlined"
        icon="download"
        onClick={() => (window.location.href = "/api/admin/audit")}
      >
        下载 audit JSON
      </Button>
      <Button
        variant="outlined"
        icon="health_and_safety"
        onClick={() => window.open("/api/health", "_blank")}
      >
        /api/health
      </Button>
    </div>
  );
}
