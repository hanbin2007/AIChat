/**
 * Signed admin session cookie. HMAC-SHA256 over the JSON payload using
 * `RELAY_SESSION_SECRET`. No external deps.
 */

import { createHmac, timingSafeEqual } from "node:crypto";
import { cookies } from "next/headers";
import { config } from "@/lib/config";

const COOKIE_NAME = "relay_session";
const MAX_AGE = 24 * 60 * 60; // 24h

export interface SessionPayload {
  sub: string; // username
  role: "operator" | "support" | "viewer";
  iat: number;
  exp: number;
}

function sign(payload: string): string {
  return createHmac("sha256", config.sessionSecret).update(payload).digest("base64url");
}

function constantTimeEqual(a: string, b: string): boolean {
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  if (bufA.length !== bufB.length) return false;
  return timingSafeEqual(bufA, bufB);
}

export function encodeSession(payload: SessionPayload): string {
  const json = Buffer.from(JSON.stringify(payload)).toString("base64url");
  return `${json}.${sign(json)}`;
}

export function decodeSession(raw: string | undefined): SessionPayload | null {
  if (!raw) return null;
  const [json, sig] = raw.split(".");
  if (!json || !sig) return null;
  if (!constantTimeEqual(sig, sign(json))) return null;
  try {
    const payload = JSON.parse(Buffer.from(json, "base64url").toString("utf8")) as SessionPayload;
    if (payload.exp < Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch {
    return null;
  }
}

export async function setSessionCookie(payload: SessionPayload): Promise<void> {
  (await cookies()).set(COOKIE_NAME, encodeSession(payload), {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: MAX_AGE,
  });
}

export async function clearSessionCookie(): Promise<void> {
  (await cookies()).delete(COOKIE_NAME);
}

export async function readSession(): Promise<SessionPayload | null> {
  const raw = (await cookies()).get(COOKIE_NAME)?.value;
  return decodeSession(raw);
}

export function makeSession(username: string, role: SessionPayload["role"] = "operator"): SessionPayload {
  const now = Math.floor(Date.now() / 1000);
  return { sub: username, role, iat: now, exp: now + MAX_AGE };
}
