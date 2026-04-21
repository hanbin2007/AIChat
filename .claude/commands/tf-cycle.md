---
description: One tick of the TestFlight → GitHub-review → fix → ship loop
---

You are the orchestrator for auto-handling TestFlight feedback for AIChat (repo `hanbin2007/AIChat`, ASC app `6760607040`, bundle `hanbin.AIChat`). Called on a cron-like schedule by `/loop`.

**Review channel is GitHub only** — no iMessage, no external messaging. The user reacts on issues (labels / comments / close). Every reaction from the user triggers action on the next tick (or sooner if they ping you in-session).

Run phases below in order; end with a one-line summary.

---

## Phase 0 — REACT (process user interactions first, highest priority)

1. Read `~/Documents/aichat/.claude/commands/tf-state.json` (create `{"cursors":{},"last_scan_iso":"<24h ago>","last_ship_iso":""}` if missing).

2. Query issues updated since `last_scan_iso`:
   ```
   gh issue list --repo hanbin2007/AIChat --state all --search "updated:>=<last_scan_iso> label:source:testflight-api" --json number,state,labels,updatedAt
   ```

3. For each updated issue:
   - If state == `closed` AND no label `shipped-to-testflight` → treat as dismissed. Add label `dismissed` if missing. Move on.
   - Otherwise fetch full issue + comments: `gh issue view <N> --json body,comments,labels,state`
   - Look at comments authored by the repo owner (`hanbin2007`) newer than `last_scan_iso`.

4. For each new owner comment, parse intent:
   - Contains `approve` (case-insensitive) + optional scheme letter `A`/`B`/`C`/`D` → add label `auto-fix-approved`. Store chosen scheme in issue body (append `<!-- scheme:X -->` via `gh issue edit --body`).
   - Contains `defer` → add label `defer`, remove `needs-fix` and `needs-review`.
   - Contains `dismiss` → close the issue.
   - Contains any other text → treat as refinement. Read the comment carefully. Respond by editing the issue body (update "我的理解" / "建议方案" section per their guidance) AND posting a `gh issue comment` saying "Got it. Updated plan: <1-2 sentences>. Reply `approve A` to proceed or comment further." Keep `needs-review` label.

5. For each label change owner made (e.g., they added `auto-fix-approved` directly without comment), just proceed — label alone is a valid approval signal.

6. Update `last_scan_iso` in state file to `now()`.

---

## Phase 1 — TRIAGE (poll TestFlight for new feedback)

1. Call MCP tool `mcp__testflight-feedback__list_feedback` with `app_id=6760607040`, `type=all`, `limit=50`.

2. For each item in response, compute dedup hash (12-char prefix of sha256) using this exact shell snippet so it matches the hashes I used on existing issues:
   - Screenshot: `printf '%s||%s' "<comment>" "<build_version>" | shasum -a 256 | cut -c1-12`
   - Crash: `printf '%s||%s' "<first 5 stack frames joined by newline>" "<build_version>" | shasum -a 256 | cut -c1-12`
   - **Important**: comment is the raw text as returned by MCP (do not trim/normalize). If screenshot has no comment but has an image URL, use the URL in place of comment.

3. Search GitHub for `[hash:<12>]` in issue titles. Hit → if the new submission is a duplicate (same hash), append a comment on the existing issue: `New duplicate submission: <id>, build <ver>`. If the existing issue is closed, reopen + add `regression` label.

4. Miss → go do the investigation:
   - Classify: `tf-bug` / `tf-feature` / `tf-other`
   - Read relevant code files to understand context (use Glob/Grep/Read; spawn Explore agent if investigation is non-trivial)
   - Write an issue body with these sections:
     - `## 原文` — exact feedback text + metadata (build/device/os/locale)
     - `## 我的理解` — your interpretation of what the tester actually wants
     - `## 涉及文件` — concrete file:line references
     - `## 建议方案` — 2-4 approaches (A/B/C/D) with trade-offs, mark recommended one
     - `## 等你回应` — options: `auto-fix-approved` + scheme letter / `defer` / close / natural language
   - Create with `gh issue create --title "[TF <kind>] <summary> [hash:<12>]" --label "tf-<kind>,source:testflight-api,needs-review<,needs-fix if bug>"`

5. Update MCP cursor state (highest feedback id seen) in `tf-state.json`.

**Caps**: max 20 new issues per tick. If feedback API returns more, file the first 20 and log warning.

---

## Phase 2 — FIX (run autofix on approved issues)

For each open issue with `auto-fix-approved` AND without `auto-fix-in-progress`:

1. Add label `auto-fix-in-progress` (prevents double-scheduling).

2. Parse chosen scheme from issue body (`<!-- scheme:X -->`). Default to scheme "A" (the recommended one) if not specified.

3. Spawn Background Agent (`Agent` tool, `subagent_type: "general-purpose"`, `isolation: "worktree"`):

   > Fix issue #<N> in hanbin2007/AIChat using scheme <X> as described in the issue's "建议方案" section. Read the issue body first — it tells you what to change and where.
   >
   > Constraints: minimal changes, no refactoring unrelated code, respect CLAUDE.md test/build procedures.
   >
   > Attempts: up to 3. After each attempt run:
   > - If Watch code changed: `xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,id=93A83695-2859-4388-B337-957616D03F55" test`
   > - If iOS code changed: `xcodebuild -project AIChat.xcodeproj -scheme "AIChat iOS App" -destination "generic/platform=iOS" build`
   > - If Relay code changed: `xcodebuild -project AIChat.xcodeproj -scheme "AIChat Relay" -destination "platform=macOS" build`
   >
   > On attempt success: commit `fix: <summary> (Fixes #<N>)` on branch `autofix/issue-<N>`, push, return branch name + short SHA + changelog (<80 chars).
   >
   > On 3 failures: do NOT commit; return a detailed report of what you tried + the failing outputs.

4. On agent return:
   - **Success**: `gh pr create --base main --head autofix/issue-<N> --title "fix(tf): <summary> (#<N>)" --body "..."`. Then `gh pr merge <PR#> --squash --auto` to queue auto-merge. Remove `auto-fix-in-progress`, add `auto-fix-ready`. Comment on issue: `Attempt succeeded → PR #<PR#> queued for merge.`
   - **Failure**: remove `auto-fix-in-progress` and `auto-fix-approved`, add `auto-fix-failed`, comment the failure report on issue. User can comment further guidance and re-approve.

---

## Phase 3 — SHIP (upload merged fixes to TestFlight)

1. Query recently-merged auto-fix PRs since `last_ship_iso`:
   ```
   gh pr list --repo hanbin2007/AIChat --state merged --label auto-fix-ready --json number,title,mergedAt,headRefName --jq '.[] | select(.mergedAt > "<last_ship_iso>")'
   ```

2. If the list is non-empty:
   - For each merged PR:
     - Get the linked issue number from commit message (`git log -1 --format=%B <PR merge sha>` → grep `Fixes #<N>`)
     - Fetch that issue: `gh issue view <N> --json title,body`
     - Extract: (a) the original feedback quote from "## 原文" section (first blockquote line), (b) the PR title summary after `fix(tf): ` prefix
   - Build changelog, one block per fix:
     ```
     修复 #<N>: <summary>
       反馈: "<original feedback one-liner>"
     ```
   - Join all blocks with blank lines. Keep total under 4000 chars (TestFlight limit); truncate oldest if over.
   - `cd ~/Documents/aichat; set -a; source fastlane/.env; set +a; fastlane beta changelog:"<changelog>"` (timeout 30 min)
   - On success: for each referenced issue, comment `Shipped in TestFlight build <ver>(<build_num>) to external group PBTestGroup.`, add label `shipped-to-testflight`, close the issue. Update `last_ship_iso`.
   - On failure: comment on each pending issue with last 3 lines of fastlane stderr; next tick will retry.

3. If no merged PRs, skip.

---

## Summary line

Always end with:
`tick OK — reacted: <N>, triaged: <M> new, fixed: <K> in progress, shipped: <J>` (or `FAILED: <reason>` if any phase hard-errored)

---

## Edge cases

- **iMessage channel events**: this loop no longer relies on iMessage. If user happens to send messages through any channel, just treat them as normal user input to the session; they don't replace GitHub as the canonical review surface.
- **Rate limits**: gh CLI uses personal token, 5000 req/h. At 1-tick-per-minute with ~10 api calls per tick = 600/h, very safe.
- **Stale state**: if `tf-state.json` gets corrupted, delete it and let next tick rebuild from current time.
