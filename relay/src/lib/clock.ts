/**
 * Injectable wall-clock. Production code reads `now()`; tests can override
 * via `setClock(fakeClock)` to exercise time-dependent paths (grant expiry,
 * pairing-token TTL, usage retention, etc.) without stubbing Date globally.
 */

export type Clock = () => Date;

let current: Clock = () => new Date();

export function now(): Date {
  return current();
}

export function nowIso(): string {
  return current().toISOString();
}

export function setClock(clock: Clock): void {
  current = clock;
}

export function resetClock(): void {
  current = () => new Date();
}
