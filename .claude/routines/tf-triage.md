---
description: Pull new TestFlight feedback, file GitHub issues
trigger: schedule (every 30 min)
---

You are the **TRIAGE** routine. Follow `_shared.md`. One run of this
routine processes up to 20 new TestFlight feedback items and files
them as GitHub issues.

## Steps

1. **Load state.** Read the `meta-state` issue body (see `_shared.md`).
   Cache `tf_feedback_cursor` locally.

2. **Pull feedback.** Call `mcp__testflight-feedback__list_feedback`
   with `app_id=6760607040`, `type=all`, `limit=50`. Filter to items
   with `id > tf_feedback_cursor`.

3. **Dedup.** For each item compute hash:
   - Screenshot: `printf '%s||%s' "<comment or image_url>" "<build_version>" | sha256sum | cut -c1-12`
   - Crash: `printf '%s||%s' "<first 5 stack frames joined by \n>" "<build_version>" | sha256sum | cut -c1-12`

   Use raw comment text — do **not** trim/normalize. If an existing
   open or closed issue has `[hash:<12>]` in title:
   - If duplicate of open issue: comment
     `@hanbin2007 New duplicate submission: <id>, build <ver>`.
   - If duplicate of closed issue: reopen + add label `regression`.
   - Skip further processing for this item.

4. **Investigate (misses only).**
   - Classify: `tf-bug` / `tf-feature` / `tf-other`.
   - Read the relevant code. For non-trivial cases spawn an Explore
     subagent with a focused query — do NOT do a breadth-first
     codebase walk, the routine has a time budget.
   - Write issue body with sections:
     - `## 原文` — exact feedback text + metadata (build/device/os/locale)
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
   ```
   gh issue create --repo hanbin2007/AIChat \
     --title "[TF <kind>] <summary> [hash:<12>]" \
     --label "tf-<kind>,source:testflight-api,needs-review<,needs-fix if bug>" \
     --body "<file>"
   ```

6. **Update state.** Set `tf_feedback_cursor` to the highest id
   processed. Set `last_triage_iso` to `now()`. Write back to the
   `meta-state` issue body.

## Caps

- Max 20 new issues per run. If more, file the first 20 and log a
  warning.
- No MCP tool call inside a dedup hit (short-circuit early).

## Summary line

End with exactly:
`triage OK — processed: <N>, new: <M>, duped: <K>, reopened: <R>`
(or `FAILED: <reason>`).
