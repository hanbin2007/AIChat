---
description: Pull new TestFlight feedback from ASC API, file GitHub issues
trigger: schedule (every 30 min)
---

You are the **TRIAGE** routine. Follow `_shared.md`. One run processes
up to 20 new TestFlight feedback items (screenshot + crash, merged
and de-duped) and files them as GitHub issues.

TestFlight feedback is pulled directly from the App Store Connect
REST API (`/v1/betaFeedbackScreenshotSubmissions` +
`/v1/betaFeedbackCrashSubmissions`) via
`.claude/routines/scripts/asc.py`. There is no MCP server to install.

## Prereqs

Env vars on this routine:
- `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` — ASC API auth
  (see `README.md`)
- `ASC_APP_ID` = `6760607040`

## Steps

1. **Load state.** Read the `meta-state` issue body (see `_shared.md`).
   Cache `last_feedback_iso` locally (empty / missing → use
   `1970-01-01T00:00:00Z`).

2. **Pull + normalize feedback.**
   ```bash
   python3 .claude/routines/scripts/asc.py feedback \
     --since "$LAST_FEEDBACK_ISO" > /tmp/feedback.json
   ```
   This merges screenshot + crash submissions, inlines
   `build_version` (marketing + buildNumber), and emits a JSON array
   of items with this shape (also in `asc.py` source):
   ```json
   {
     "kind": "screenshot|crash",
     "id": "<asc-uuid>",
     "created": "2026-04-23T01:23:45Z",
     "comment": "<tester comment>",
     "stack_head": "<first 5 crash log lines joined by \\n>",
     "build_version": "2.1(42)",
     "device_model": "Apple Watch Series 11",
     "os_version": "watchOS 26.0",
     "locale": "zh-Hans_CN",
     "image_url": "",
     "hash": "a1b2c3d4e5f6"
   }
   ```
   The `hash` field is the 12-char dedup key — computed by `asc.py`
   using the exact same formula as the legacy local orchestrator
   (`sha256(comment_or_url || build_version)` for screenshots,
   `sha256(stack_head || build_version)` for crashes).

3. **Dedup against existing issues.**
   For each item, search GitHub for `[hash:<12>]` in issue titles:
   ```bash
   gh issue list --repo hanbin2007/AIChat --state all \
     --search "[hash:$HASH] in:title" --json number,state,labels
   ```
   - Open issue with same hash → comment
     `@hanbin2007 New duplicate submission: <id>, build <ver>`. Skip.
   - Closed issue with same hash → reopen, add label `regression`,
     comment as above. Skip.
   - Miss → proceed to step 4.

4. **Investigate (misses only).**
   - Classify: `tf-bug` / `tf-feature` / `tf-other`.
   - Read the relevant code. For non-trivial cases spawn an Explore
     subagent with a focused query — do NOT do a breadth-first
     codebase walk, the routine has a time budget.
   - Write issue body with sections:
     - `## 原文` — exact feedback text + metadata (build, device,
       os, locale). For crashes include the first 5 stack frames
       from `stack_head`. For screenshots with no comment, note the
       image URL.
     - `## 我的理解` — what state transition failed / which invariant
       was violated / which concurrency or platform assumption broke.
       Full Production-Quality Contract (see `_shared.md`).
     - `## 涉及文件` — concrete `file:line` references. List every
       target that compiles the touched code (Watch / iOS / Relay /
       Shared Licensing); if only one, say why.
     - `## 建议方案` — 2-4 approaches labeled A/B/C/D with
       trade-offs. Mark recommended. Each spec: code change,
       cross-target impact, new/changed test, observability,
       concurrency. Recommended must satisfy the full Contract.
     - `## 等你回应` — options: `approve A` / `defer` / close /
       natural language.

5. **File.**
   ```bash
   gh issue create --repo hanbin2007/AIChat \
     --title "[TF <kind>] <summary> [hash:<12>]" \
     --label "tf-<kind>,source:testflight-api,needs-review<,needs-fix if bug>" \
     --body "<file>"
   ```

6. **Update state.** Set `last_feedback_iso` to the highest `created`
   value seen (even for duplicates, so we don't reprocess them).
   Set `last_triage_iso = now()`. Write back to the `meta-state`
   issue body.

## Caps

- Max 20 new issues per run. If more, file the first 20 (oldest first,
  since the list is sorted ascending) and log a warning — next tick
  picks up the rest naturally.

## Summary line

End with exactly:
`triage OK — processed: <N>, new: <M>, duped: <K>, reopened: <R>`
(or `FAILED: <reason>`).
