import { config } from "@/lib/config";

const MASK = "••••••";

export function mask(value: string | undefined, keep = 6): string {
  if (!value) return "";
  if (value.length <= keep) return MASK;
  return `${MASK}${value.slice(-keep)}`;
}

export function stripAuthHeader(headers: Record<string, string>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(headers)) {
    if (k.toLowerCase() === "authorization") {
      out[k] = `Bearer ${mask(v.replace(/^Bearer\s+/i, ""))}`;
    } else {
      out[k] = v;
    }
  }
  return out;
}

/** Remove known sensitive values from a JSON-ish string. */
export function redactSensitive(text: string, extraPatterns: RegExp[] = []): string {
  let out = text;
  if (config.geminiApiKey) {
    out = out.split(config.geminiApiKey).join(mask(config.geminiApiKey));
  }
  if (config.relayBearerToken) {
    out = out.split(config.relayBearerToken).join(mask(config.relayBearerToken));
  }
  for (const pattern of extraPatterns) {
    out = out.replace(pattern, (match) => mask(match));
  }
  return out;
}

/** Compile a list of redaction-rule strings into RegExps, skipping invalid entries. */
export function compileRedactionPatterns(
  rules: { name: string; pattern: string; enabled: boolean }[] | undefined,
): RegExp[] {
  if (!rules) return [];
  const out: RegExp[] = [];
  for (const r of rules) {
    if (!r.enabled) continue;
    try {
      out.push(new RegExp(r.pattern, "g"));
    } catch {
      // Skip invalid user-provided patterns silently.
    }
  }
  return out;
}
