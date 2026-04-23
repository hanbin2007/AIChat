/** Accept either snake_case or camelCase on the wire (matches Swift Codable). */
export function pick<T = unknown>(obj: Record<string, unknown> | undefined, ...keys: string[]): T | undefined {
  if (!obj) return undefined;
  for (const key of keys) {
    if (key in obj && obj[key] !== undefined) return obj[key] as T;
  }
  return undefined;
}
