import { beforeEach, describe, expect, it } from "vitest";
import { metrics } from "@/lib/observability/metrics";
import { resetState } from "../helpers";

describe("metrics", () => {
  beforeEach(resetState);

  it("aggregates counters by label", () => {
    const m = metrics();
    m.incCounter("reqs", 1, { path: "/a" });
    m.incCounter("reqs", 2, { path: "/a" });
    m.incCounter("reqs", 1, { path: "/b" });
    const snap = m.snapshot();
    const a = snap.counters.find((c) => c.labels?.path === "/a");
    const b = snap.counters.find((c) => c.labels?.path === "/b");
    expect(a?.value).toBe(3);
    expect(b?.value).toBe(1);
  });

  it("observe / percentile returns the expected quantile", () => {
    const m = metrics();
    for (let i = 1; i <= 100; i++) m.observe("lat", i);
    expect(m.percentile("lat", 50)).toBeGreaterThan(40);
    expect(m.percentile("lat", 50)).toBeLessThan(60);
    expect(m.percentile("lat", 95)).toBeGreaterThan(90);
  });

  it("percentile on an empty histogram returns 0", () => {
    expect(metrics().percentile("never", 95)).toBe(0);
  });

  it("render emits Prometheus exposition format", () => {
    const m = metrics();
    m.incCounter("reqs", 1, { path: "/x" });
    m.setGauge("inflight", 4);
    const out = m.render();
    expect(out).toContain("# TYPE reqs counter");
    expect(out).toContain('reqs{path="/x"} 1');
    expect(out).toContain("# TYPE inflight gauge");
    expect(out).toContain("inflight 4");
  });
});
