/**
 * Extremely small Prometheus-compatible exposition. We don't depend on a
 * third-party client — counters live in memory and are rendered on demand.
 */

interface CounterState {
  value: number;
  labels?: Record<string, string>;
}

class Metrics {
  private counters = new Map<string, CounterState>();
  private gauges = new Map<string, number>();
  private histograms = new Map<string, number[]>();

  incCounter(name: string, by = 1, labels?: Record<string, string>) {
    const key = this.key(name, labels);
    const prev = this.counters.get(key)?.value ?? 0;
    this.counters.set(key, { value: prev + by, labels });
  }

  setGauge(name: string, value: number) {
    this.gauges.set(name, value);
  }

  observe(name: string, value: number) {
    const arr = this.histograms.get(name) ?? [];
    arr.push(value);
    if (arr.length > 1024) arr.shift();
    this.histograms.set(name, arr);
  }

  percentile(name: string, p: number): number {
    const arr = this.histograms.get(name);
    if (!arr || arr.length === 0) return 0;
    const sorted = [...arr].sort((a, b) => a - b);
    const index = Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length));
    return sorted[index];
  }

  render(): string {
    const lines: string[] = [];
    for (const [key, state] of this.counters) {
      const { name, labelString } = this.parseKey(key);
      lines.push(`# TYPE ${name} counter`);
      lines.push(`${name}${labelString} ${state.value}`);
    }
    for (const [name, value] of this.gauges) {
      lines.push(`# TYPE ${name} gauge`);
      lines.push(`${name} ${value}`);
    }
    return lines.join("\n") + "\n";
  }

  snapshot() {
    return {
      counters: Array.from(this.counters.entries()).map(([key, state]) => ({ key, ...state })),
      gauges: Object.fromEntries(this.gauges),
      p50Latency: this.percentile("chat_latency_ms", 50),
      p95Latency: this.percentile("chat_latency_ms", 95),
    };
  }

  private key(name: string, labels?: Record<string, string>): string {
    if (!labels) return name;
    const serialized = Object.entries(labels)
      .sort()
      .map(([k, v]) => `${k}=${v}`)
      .join(",");
    return `${name}|${serialized}`;
  }

  private parseKey(key: string): { name: string; labelString: string } {
    const [name, labels] = key.split("|");
    if (!labels) return { name, labelString: "" };
    const pairs = labels.split(",").map((p) => {
      const [k, v] = p.split("=");
      return `${k}="${v.replace(/"/g, '\\"')}"`;
    });
    return { name, labelString: `{${pairs.join(",")}}` };
  }
}

declare global {
  // eslint-disable-next-line no-var
  var __metrics: Metrics | undefined;
}

export function metrics(): Metrics {
  if (!globalThis.__metrics) globalThis.__metrics = new Metrics();
  return globalThis.__metrics;
}
