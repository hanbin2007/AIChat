#!/usr/bin/env python3
"""
ASC helper — one tool for everything the tf-cycle routines need from
App Store Connect: JWT minting, generic GET, TestFlight feedback
listing, Xcode Cloud build-run polling.

Usage (from a routine's bash):
    python3 .claude/routines/scripts/asc.py jwt
    python3 .claude/routines/scripts/asc.py get /v1/ciBuildRuns/<id>
    python3 .claude/routines/scripts/asc.py feedback --since 2026-04-01T00:00:00Z
    python3 .claude/routines/scripts/asc.py build-log --run <id>

Required env vars:
    ASC_KEY_ID            10-char key id from ASC → Users & Access → Integrations
    ASC_ISSUER_ID         issuer UUID from the same page
    ASC_PRIVATE_KEY       full contents of the .p8 file (PEM, with BEGIN/END lines)
    ASC_APP_ID            ASC app id (defaults to AIChat's 6760607040)
    ASC_PRODUCT_ID        Xcode Cloud product id (only needed for ship-* / build-*)
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request

# --- deps: auto-install on first run (Routines sandbox may be minimal) ---
try:
    import jwt  # PyJWT
    from cryptography.hazmat.primitives.serialization import load_pem_private_key  # noqa: F401
except ImportError:
    subprocess.check_call(
        [sys.executable, "-m", "pip", "install", "-q", "pyjwt>=2.8", "cryptography>=41"]
    )
    import jwt

DEFAULT_BASE = "https://api.appstoreconnect.apple.com"
# Override in routine env when the runtime sandbox can't reach Apple directly
# (Anthropic egress IPs return 503 on apple.com regardless of network tier).
# Point at the user's relay's `/api/asc` proxy, e.g. `https://ai.origenclub.cn/api/asc`.
BASE = os.environ.get("ASC_BASE_URL", DEFAULT_BASE).rstrip("/")

# AIChat ASC app id. Public-ish (visible in App Store URLs); no reason to
# carry it as a secret env var on every routine and in repo Actions secrets.
DEFAULT_APP_ID = "6760607040"


def _env(name: str, default: str | None = None) -> str:
    v = os.environ.get(name) or default
    if not v:
        sys.exit(f"asc.py: missing env var {name}")
    return v


def mint_jwt() -> str:
    now = int(time.time())
    return jwt.encode(
        {
            "iss": _env("ASC_ISSUER_ID"),
            "iat": now,
            "exp": now + 900,  # 15 min, well under Apple's 20 min cap
            "aud": "appstoreconnect-v1",
        },
        _env("ASC_PRIVATE_KEY"),
        algorithm="ES256",
        headers={"kid": _env("ASC_KEY_ID"), "typ": "JWT"},
    )


def asc_get(path: str) -> dict:
    url = BASE + path if path.startswith("/") else path
    req = urllib.request.Request(
        url, headers={"Authorization": f"Bearer {mint_jwt()}"}
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


# ---------------- TestFlight feedback ----------------

def _dedup_hash(kind: str, payload: str, build_ver: str) -> str:
    # Build version is intentionally NOT in the hash. The same complaint
    # surfacing on a newer build must collapse to the same hash so the
    # triage routine recognizes it (and reopens-as-regression a closed
    # issue) instead of filing a fresh duplicate. `build_ver` stays in
    # the signature for API stability — callers still pass it but it
    # doesn't influence the key. `kind` keeps screenshot vs crash
    # disjoint even when an empty payload would otherwise collide.
    _ = build_ver
    h = hashlib.sha256(f"{kind}||{payload}".encode()).hexdigest()
    return h[:12]


_PRERELEASE_CACHE: dict[str, str] = {}


def _marketing_version(build_id: str) -> str:
    """Marketing version (e.g., 2.2) lives on the build's preReleaseVersion;
    the feedback list endpoint rejects nested includes so we resolve here.
    Cached per process to avoid N+1 calls when many feedbacks share a build.
    """
    if build_id in _PRERELEASE_CACHE:
        return _PRERELEASE_CACHE[build_id]
    try:
        pr = asc_get(f"/v1/builds/{build_id}/preReleaseVersion").get("data") or {}
        ver = pr.get("attributes", {}).get("version", "?")
    except Exception:
        ver = "?"
    _PRERELEASE_CACHE[build_id] = ver
    return ver


def _resolve_build(included: list[dict], build_id: str) -> str:
    for item in included:
        if item.get("type") == "builds" and item.get("id") == build_id:
            build_no = item.get("attributes", {}).get("version", "?")
            return f"{_marketing_version(build_id)}({build_no})"
    return build_id  # fall back to raw id if not included


def _fetch_until(start_path: str, since_iso: str) -> tuple[list[dict], list[dict]]:
    """Walk `links.next` until a page contains an item ≤ since_iso (results
    are descending by createdDate, so no later page can contribute).
    Returns merged `data` (still descending) and `included` arrays.
    """
    data: list[dict] = []
    included: list[dict] = []
    url = start_path
    while url:
        page = asc_get(url)
        page_data = page.get("data", [])
        data.extend(page_data)
        included.extend(page.get("included", []))
        # Stop early if the youngest item we saw on this page is already
        # at-or-below the cursor — older items can't be newer than it.
        if any(d.get("attributes", {}).get("createdDate", "") <= since_iso
               for d in page_data):
            break
        nxt = page.get("links", {}).get("next")
        if not nxt:
            break
        url = nxt[len(BASE):] if nxt.startswith(BASE) else nxt
    return data, included


def list_feedback(since_iso: str) -> list[dict]:
    """Merge screenshot + crash feedback from ASC, normalize, dedup-hash.
    Returns items with `created > since_iso`, sorted ascending by created.
    """
    app_id = _env("ASC_APP_ID", DEFAULT_APP_ID)
    # The top-level /v1/betaFeedback*Submissions endpoints only support
    # GET_INSTANCE/DELETE; listing must go through the app relationship
    # path or Apple returns 403 "does not allow GET_COLLECTION".
    common_q = "limit=200&sort=-createdDate&include=build,tester"

    ss_data, ss_inc = _fetch_until(
        f"/v1/apps/{app_id}/betaFeedbackScreenshotSubmissions?{common_q}",
        since_iso,
    )
    # Crash list does not allow `include=crashLog`; fetch per-instance below.
    cr_data, cr_inc = _fetch_until(
        f"/v1/apps/{app_id}/betaFeedbackCrashSubmissions?{common_q}",
        since_iso,
    )

    items = []

    for d in ss_data:
        created = d.get("attributes", {}).get("createdDate", "")
        if created <= since_iso:
            continue
        attrs = d.get("attributes", {})
        build_id = (d.get("relationships", {})
                     .get("build", {})
                     .get("data", {}) or {}).get("id", "")
        build_ver = _resolve_build(ss_inc, build_id) if build_id else "unknown"
        comment = attrs.get("comment") or ""
        # If comment is empty, fall back to the first screenshot URL so the
        # dedup hash is still stable.
        image_url = ""
        for s in attrs.get("screenshots") or []:
            u = (s or {}).get("imageAssets", [{}])[0].get("url")
            if u:
                image_url = u
                break
        payload = comment or image_url
        items.append({
            "kind": "screenshot",
            "id": d.get("id"),
            "created": created,
            "comment": comment,
            "stack_head": "",
            "build_version": build_ver,
            "device_model": attrs.get("deviceModel"),
            "device_family": attrs.get("deviceFamily"),
            "os_version": attrs.get("osVersion"),
            "locale": attrs.get("locale"),
            "image_url": image_url,
            "hash": _dedup_hash("screenshot", payload, build_ver),
        })

    # `include=crashLog` is rejected on the list endpoint, so we resolve the
    # crash log id via the per-instance fetch then download the log content.
    def _crash_stack_head(crash_id: str) -> str:
        try:
            inst = asc_get(
                f"/v1/betaFeedbackCrashSubmissions/{crash_id}?include=crashLog"
            )
        except Exception:
            return ""
        for item in inst.get("included", []):
            if item.get("type") == "betaFeedbackCrashLogs":
                text = item.get("attributes", {}).get("content", "") or ""
                lines = [ln for ln in text.splitlines() if ln.strip()]
                return "\n".join(lines[:5])
        return ""

    for d in cr_data:
        created = d.get("attributes", {}).get("createdDate", "")
        if created <= since_iso:
            continue
        attrs = d.get("attributes", {})
        build_id = (d.get("relationships", {})
                     .get("build", {})
                     .get("data", {}) or {}).get("id", "")
        build_ver = _resolve_build(cr_inc, build_id) if build_id else "unknown"
        stack_head = _crash_stack_head(d.get("id", ""))
        items.append({
            "kind": "crash",
            "id": d.get("id"),
            "created": created,
            "comment": "",
            "stack_head": stack_head,
            "build_version": build_ver,
            "device_model": attrs.get("deviceModel"),
            "device_family": attrs.get("deviceFamily"),
            "os_version": attrs.get("osVersion"),
            "locale": attrs.get("locale"),
            "image_url": "",
            "hash": _dedup_hash("crash", stack_head, build_ver),
        })

    items.sort(key=lambda x: x["created"])
    return items


# ---------------- Xcode Cloud ----------------

def build_log_urls(run_id: str) -> list[str]:
    actions = asc_get(f"/v1/ciBuildRuns/{run_id}/actions").get("data", [])
    urls = []
    for a in actions:
        status = a.get("attributes", {}).get("completionStatus")
        if status not in ("FAILED", "ERRORED", None):
            continue
        arts = asc_get(f"/v1/ciBuildActions/{a['id']}/artifacts").get("data", [])
        for art in arts:
            ft = art.get("attributes", {}).get("fileType") or ""
            if ft.upper() in ("LOG", "LOGARCHIVE"):
                u = art.get("attributes", {}).get("downloadUrl")
                if u:
                    urls.append(u)
    return urls


def list_artifacts(run_id: str) -> list[dict]:
    """All artifacts attached to a build run's actions, with download URLs.

    Used by the GitHub Actions ui-screenshots bridge to find the
    ci_artifacts/ui-screenshots/ bundle published by ci_post_xcodebuild.sh.
    """
    actions = asc_get(f"/v1/ciBuildRuns/{run_id}/actions").get("data", [])
    out: list[dict] = []
    for a in actions:
        action_attrs = a.get("attributes") or {}
        action_id = a.get("id")
        arts = asc_get(f"/v1/ciBuildActions/{action_id}/artifacts").get("data", [])
        for art in arts:
            attrs = art.get("attributes") or {}
            out.append({
                "actionId": action_id,
                "actionName": action_attrs.get("name"),
                "actionType": action_attrs.get("actionType"),
                "actionStatus": action_attrs.get("completionStatus"),
                "fileName": attrs.get("fileName"),
                "fileType": attrs.get("fileType"),
                "fileSize": attrs.get("fileSize"),
                "downloadUrl": attrs.get("downloadUrl"),
            })
    return out


# ---------------- CLI ----------------

def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("jwt", help="Print a fresh JWT")

    g = sub.add_parser("get", help="GET an ASC endpoint, print JSON")
    g.add_argument("path")

    f = sub.add_parser("feedback", help="List normalized TF feedback")
    f.add_argument("--since", required=True,
                   help="ISO timestamp; items with created > since are returned")

    bl = sub.add_parser("build-log",
                        help="Print downloadable log URLs for a buildRun")
    bl.add_argument("--run", required=True)

    arts = sub.add_parser("artifacts",
                          help="List all artifacts of a buildRun as JSON")
    arts.add_argument("--run", required=True)

    args = p.parse_args()

    if args.cmd == "jwt":
        print(mint_jwt())
    elif args.cmd == "get":
        print(json.dumps(asc_get(args.path), indent=2, ensure_ascii=False))
    elif args.cmd == "feedback":
        print(json.dumps(list_feedback(args.since), indent=2, ensure_ascii=False))
    elif args.cmd == "build-log":
        for u in build_log_urls(args.run):
            print(u)
    elif args.cmd == "artifacts":
        print(json.dumps(list_artifacts(args.run), indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
