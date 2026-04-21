---
description: One tick of the TestFlight → GitHub-review → fix → ship loop
---

You are the orchestrator for auto-handling TestFlight feedback for AIChat (repo `hanbin2007/AIChat`, ASC app `6760607040`, bundle `hanbin.AIChat`). Called on a cron-like schedule by `/loop`.

**Review channel is GitHub only** — no iMessage, no external messaging. The user reacts on issues (labels / comments / close). Every reaction from the user triggers action on the next tick (or sooner if they ping you in-session).

Run phases below in order; end with a one-line summary.

---

## Production-Quality Contract (applies to every investigation and fix)

Every agent — Phase 1 triage writer, Phase 2 autofix — must hold to these. Surface-level patches that only silence the immediate symptom are not acceptable.

1. **Root-cause, not symptom.** Trace why the bug happens, which invariant got violated, which state transition was unguarded. A fix that "makes this crash go away" without explaining the mechanism gets rejected.

2. **Cross-platform audit.** AIChat has four targets: `AIChat Watch App` (watchOS primary), `AIChat iOS App` (companion), `AIChat Relay` (macOS server), `Shared Licensing` (cross-platform). Any change to shared code, `ChatStore`, models, or services must be verified against every target that compiles it — build all affected schemes. UI work must call out sizing/input-modality adaptation (Digital Crown, 46mm screen, touch vs pointer).

3. **Concurrency and failure paths.** Call out `@MainActor` boundaries, `Task` lifetimes, `async` re-entrancy, cancellation, and what happens on: cold launch, low memory, bg→fg, iCloud latency, network timeout, empty input, storage corruption. If the bug exists because one of these wasn't considered, name it.

4. **Tests pin the invariant, and they must pass strictly.** Production fixes ship with a regression test that would have caught the bug. watchOS 26 test runners require `async throws` (see CLAUDE.md). Every relevant scheme's tests must go green — no flaky-retry acceptance, no "known failure" suppression. However, **tests are a means, not the end** — the actual goal is that the tester's real-world problem is resolved. If an existing test is itself buggy (wrong expectation, racy setup, stale invariant, broken fixture) and blocks a legitimate fix, the agent may edit or delete the test as part of the change, but must explain the reason in the commit message and PR body. Do not silence a test just to pass CI; the bar is that the user's complaint actually stops happening.

5. **No dead code, no unused feature flags, no half-refactors.** Don't leave commented-out old code. Don't introduce abstractions "for future use."

6. **Observability when the failure was invisible.** If the user saw a silent bad state (blank list, unrendered text, wrong status), the fix considers whether a log or assertion would have shortened next diagnosis.

7. **Security where relevant.** Tokens, keys, user data, IPC — never widen access, never log secrets, never trust relay client input on the server side.

These are non-negotiable. Phase 1 writes them into the 建议方案 section. Phase 2 agents re-verify before commit.

---

## Phase 0 — REACT (process user interactions first, highest priority)

**Before anything else (pre-phase 0, runs every tick):**

Check free disk on `/` with `df -h / | awk 'NR==2 {print $4}'`. If under 10 GB, auto-clean in this order, stopping as soon as 20 GB is free:

1. `rm -rf ~/Library/Developer/Xcode/DerivedData/*` — Xcode rebuilds, typically 2–50 GB reclaimed.
2. Remove stale autofix worktrees under `/Users/zhb/Documents/AIChat/.claude/worktrees/agent-*` whose agent_id prefix is NOT in the current `in_flight` dict:
   ```
   git worktree remove -f -f <path>     # may need double -f for locked worktrees
   rm -rf <path>                         # if worktree command fails (e.g. dangling lock)
   ```
   **Do NOT touch** `/Users/zhb/.codex/worktrees/...` or `/Users/zhb/Documents/AIChat/.claude/worktrees/{gallant-brattain,sharp-shirley,...}` — those are the user's own branches/sessions.
3. Remove autofix PR branches that are already merged on origin: `git branch -D autofix/issue-<N>` for any `<N>` whose PR state is `MERGED`.

Log one line ("disk cleanup: freed X GB, removed Y worktrees") so the tick summary can mention it. Never prompt — this is routine hygiene. Blocked `xcodebuild` (ENOSPC) is the most common failure mode of the whole loop; proactive cleanup avoids it.

**After cleanup, sync local main with origin:**
```
cd /Users/zhb/Documents/aichat
git fetch origin main --quiet
LOCAL=$(git rev-parse main)
REMOTE=$(git rev-parse origin/main)
if [ "$LOCAL" = "$REMOTE" ]; then
  :  # already in sync
elif git merge-base --is-ancestor main origin/main; then
  # Local strictly behind. Attempt ff. If the working tree has changes that
  # overlap incoming, ff-only will refuse — capture stderr, flag in summary.
  FF_OUT=$(git merge --ff-only origin/main 2>&1)
  FF_RC=$?
  if [ $FF_RC -ne 0 ]; then
    # Do NOT swallow. Flag and stop syncing — something is dirty in a way that needs user attention.
    echo "WARN: ff-only failed, local main stays at $LOCAL. stderr: $FF_OUT"
    SYNC_STATUS="ff-blocked"
  else
    SYNC_STATUS="fast-forwarded"
  fi
elif git merge-base --is-ancestor origin/main main; then
  # Local is ahead (has unpushed commits). Don't auto-push; flag.
  SYNC_STATUS="local-ahead ($(git rev-list origin/main..main | wc -l) unpushed)"
else
  # Real divergence — both sides have commits the other doesn't.
  SYNC_STATUS="diverged"
fi
```

Surface `SYNC_STATUS` in the tick summary line. Never rebase automatically. Never force-push. Never stash-and-merge silently. The whole point: tick-time sync is conservative — when in doubt, leave things alone and let the human or the next deliberate action sort it out.

**Long-running agents on stale base** (risk #2): when you spawn a Phase 2 agent, the worktree starts at whatever `origin/main` was at spawn time. If origin/main advances before the agent's PR merges, GitHub will mark the PR `BEHIND`. `gh pr merge --squash --auto` handles most cases (auto-merges when the base is updated). If the agent's branch has actual conflicts with new commits on main, re-merge fails and the PR sits open with a `conflicts` indicator. At that point Phase 2A should:
- Detect via `gh pr view <PR#> --json mergeStateStatus` → `DIRTY`
- Post `@hanbin2007 PR #<N> now conflicts with main after rebase. Leaving for manual resolution.` on the issue
- Leave `in_flight[<N>]` with `phase="pr_conflicted"` until human clears it

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
   - Contains any other text → treat as refinement. Read the comment carefully. Respond by editing the issue body (update "我的理解" / "建议方案" section per their guidance) AND posting a `gh issue comment` saying "@hanbin2007 Got it. Updated plan: <1-2 sentences>. Reply `approve A` to proceed or comment further." Keep `needs-review` label.

**Every reply comment you post must start with `@hanbin2007 `** — this is how the owner gets the GitHub push notification on mobile. Applies to refinement replies, approval acks, autofix-started/succeeded/failed comments, ship notifications — all of them.

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
     - `## 我的理解` — your interpretation of the tester's intent, written under the Production-Quality Contract above: what state transition failed, which invariant was violated, which concurrency/platform assumption broke. Do NOT stop at "X doesn't show" — explain mechanism.
     - `## 涉及文件` — concrete file:line references. **Every target that compiles the touched code must be listed** (Watch App / iOS App / Relay / Shared Licensing). If only one target is affected, say why the others aren't.
     - `## 建议方案` — 2-4 approaches (A/B/C/D) with trade-offs, mark recommended one. Each approach specifies: code change, cross-platform impact (which targets rebuild, what to verify on each), new/changed test(s), observability addition if any, concurrency considerations. Recommended approach must meet the full Production-Quality Contract.
     - `## 等你回应` — options: `auto-fix-approved` + scheme letter / `defer` / close / natural language
   - Create with `gh issue create --title "[TF <kind>] <summary> [hash:<12>]" --label "tf-<kind>,source:testflight-api,needs-review<,needs-fix if bug>"`

5. Update MCP cursor state (highest feedback id seen) in `tf-state.json`.

**Caps**: max 20 new issues per tick. If feedback API returns more, file the first 20 and log warning.

---

## Phase 2 — FIX (parallel autofix on approved issues)

**State shape**: `tf-state.json.in_flight` is a dict keyed by issue number:
```
"in_flight": {
  "1": {"agent_id": "...", "phase": "agent_running"|"test_running"|"pr_queued", "worktree": "...", "started": "ISO"},
  "3": {...}
}
```

Each tick runs these three sub-steps IN ORDER:

### 2A. Advance in-flight entries (non-blocking)

For each `<N> -> entry` in `in_flight`:

- Phase `agent_running`: call `TaskOutput(task_id=entry.agent_id, block=false, timeout=0)`.
  - `status=running` → skip.
  - `status=completed` with SUCCESS block → parse branch + SHA, create PR (`gh pr create ...`), queue auto-merge (`gh pr merge <PR#> --squash --auto`), swap labels on issue (`auto-fix-in-progress` off, `auto-fix-ready` on), comment `Attempt succeeded → PR #<PR#> queued for merge.`, move entry.phase to `pr_queued` (or delete entry if PR already merged).
  - `status=completed` with FAILED block → remove `auto-fix-in-progress` and `auto-fix-approved`, add `auto-fix-failed`, comment the failure report, delete entry.

- Phase `pr_queued`: check if PR merged. If yes, delete entry (Phase 3 will handle ship separately).

### 2B. Start new agents for newly approved issues

Compute `approved_set = {open issues with auto-fix-approved label}` minus `in_flight.keys()`.

**Concurrency cap**: at most 3 agents running simultaneously. If `len(in_flight) >= 3`, skip until next tick.

For each issue `<N>` in `approved_set` (up to the cap):

1. Add label `auto-fix-in-progress` (prevents double-scheduling).
2. Parse scheme from body (`<!-- scheme:X -->`); default to A.
3. Spawn agent with `run_in_background: true`:
   ```
   Agent(
     subagent_type: "general-purpose",
     isolation: "worktree",
     run_in_background: true,
     description: "autofix #<N>",
     prompt: "<full prompt — see template below>"
   )
   ```
4. Record entry: `in_flight[<N>] = {agent_id, phase:"agent_running", worktree, started: now()}`.

**Agent prompt template** (inline, no var substitution ambiguity — construct in Python):
> Fix issue #<N> in hanbin2007/AIChat using scheme <X> as described in the issue's "建议方案" section.
>
> Start: `gh issue view <N> --repo hanbin2007/AIChat --json body -q .body` to read the full issue.
>
> You are held to the **Production-Quality Contract** in `.claude/commands/tf-cycle.md`:
> - Fix the root cause, not the symptom. If the scheme description is surface-level, go deeper before committing.
> - Audit every target that compiles the touched code (Watch App / iOS App / Relay / Shared Licensing). Build each one that's affected.
> - Consider concurrency, @MainActor boundaries, async re-entrancy, cancellation, and failure paths.
> - Ship a regression test (async throws for watchOS 26).
> - No dead code, no commented-out blocks, no unused flags.
> - Add a log or assertion if the failure was silent.
> Re-read the Contract before your FINAL commit and verify each item applies.
>
> Constraints: stay within scope (the issue's approved scheme). Don't refactor unrelated code. Respect CLAUDE.md.
>
> **Two-way conversation with the owner via the issue (required):**
>
> *You → owner (progress):* post a short `@hanbin2007`-prefixed comment on issue #<N> at these moments so the owner sees progress from GitHub notifications on mobile:
> 1. **Start**: one line naming the approach ("Starting: <one sentence on what I'm changing>, <which targets will rebuild>").
> 2. **After each build/test run** (pass or fail): one line with the outcome — e.g. `Attempt 1 build ✅, tests 🟡 (2 flaky), iterating` or `Attempt 2 build ❌ (ChatStore type mismatch), investigating`.
> 3. **Scope or approach pivot**: comment `Pivoting: <why + what now>` BEFORE acting.
> 4. **Stuck > 15 min without progress**: post a specific question or options — `Stuck on: <symptom>. Option A: <>. Option B: <>. Going with A unless you say otherwise within this attempt.`
> 5. **Ambiguous decision**: any time you're choosing between two reasonable paths, ask — don't silently pick.
>
> *Owner → you (direction):* the host runs a GitHub webhook relay daemon (see "Deployment" section) that writes a new line to `/tmp/aichat-gh-events.log` **every time** the owner touches issue #<N> (comment, label, close). Watch that log — don't poll the GitHub API.
>
> Check the log at **all** of these moments:
>
> 1. **Start of every attempt** (before touching files). Snapshot: `WATERMARK=$(wc -l < /tmp/aichat-gh-events.log)`. If any lines exist since your last snapshot, fetch the latest owner comments with `gh issue view <N> --json comments -q '[.comments[] | select(.author.login=="hanbin2007")] | .[-3:]'`.
> 2. **Before `git commit`** (last chance to catch late direction).
> 3. **Passively during long waits** using `tail -f` in your wait loop. While an xcodebuild run is in progress (>2 min), run your waiter as:
>    ```
>    # wait for either: test output written OR new log line after WATERMARK
>    until [ -s "$BUILD_OUT" ] && ! ps -p "$BUILD_PID" > /dev/null; do
>      sleep 30
>      NEW=$(tail -n +$((WATERMARK+1)) /tmp/aichat-gh-events.log | wc -l)
>      if [ "$NEW" -gt 0 ]; then
>        WATERMARK=$(wc -l < /tmp/aichat-gh-events.log)
>        # One gh call after detecting activity — not on every sleep
>        LATEST=$(gh issue view <N> --json comments -q '.comments[-1] | select(.author.login=="hanbin2007")')
>        if [ -n "$LATEST" ]; then
>          # Decide: kill / ack / keep going
>          :
>        fi
>      fi
>    done
>    ```
>    Rule: if a new owner comment tells you to **stop / pivot / change scope**, kill the in-flight xcodebuild (`kill <pid>` or TaskStop), post an ack comment, and act on the new direction.
>
> The log is the trigger (cheap local tail); `gh issue view` is only called once per log-activity burst (cheap API usage). If any found comment is newer than your last progress comment and contains direction, **adapt and reply** `@hanbin2007 Got it — <what I'm doing differently>`. Never silently ignore. Never wait/block — if you posted a question and there's no reply yet, proceed with your best interpretation and say so.
>
> *Rules:* terse (<200 chars), always `@hanbin2007` prefix, no code blocks in conversation comments (save those for the final SUCCESS/FAILED block). Under ~8 total comments per agent lifetime. Never post from a scratch buffer — only after a real signal (build exit code, test result, decision point, new owner comment). The final SUCCESS/FAILED comment posted by the orchestrator is separate.
>
> Use: `gh issue comment <N> --repo hanbin2007/AIChat --body "@hanbin2007 <message>"`
>
> Attempts: up to 3. After each attempt, build **every affected target** and run tests on the relevant ones:
> - Watch code changed: build + `xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,id=93A83695-2859-4388-B337-957616D03F55" test`
> - iOS code changed: `xcodebuild -project AIChat.xcodeproj -scheme "AIChat iOS App" -destination "generic/platform=iOS" build`
> - Relay code changed: `xcodebuild -project AIChat.xcodeproj -scheme "AIChat Relay" -destination "platform=macOS" build`
> - Shared Licensing changed: build all three above (it compiles into each).
>
> On success: `git checkout -b autofix/issue-<N>`; commit `fix: <summary> (Fixes #<N>)`; `git push -u origin autofix/issue-<N>`. Return EXACTLY:
> ```
> SUCCESS
> branch: autofix/issue-<N>
> sha: <short>
> changelog: <under 80 chars>
> files_changed: <comma list>
> ```
>
> On 3 failures: do NOT commit. Return EXACTLY:
> ```
> FAILED
> attempts: 3
> last_error: |
>   <last 30 lines of failing output>
> what_i_tried:
>   - ...
> next_suggestion: <one line>
> ```

### 2C. Invariants

- A single issue can be in `in_flight` at most once.
- A worktree is created per agent by the `isolation: "worktree"` option; never shared across agents.
- If the conversation dies mid-flight, the in_flight dict points to orphaned agent IDs — next tick should call `TaskOutput` on each; if it reports `not_found`, delete the entry and revert labels (`auto-fix-in-progress` off, `auto-fix-approved` back on if you want re-triage).

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
- **Rate limits**: gh CLI uses personal token, 5000 req/h. At 1-tick-per-minute with ~10 api calls per tick = 600/h, very safe. Event-driven mode (default) uses even less.
- **Stale state**: if `tf-state.json` gets corrupted, delete it and let next tick rebuild from current time.

---

## Deployment — event-driven `/loop` (current architecture)

The per-minute cron was replaced with a webhook-driven dynamic loop. The orchestrator wakes on actual GitHub activity plus a 30-min idle heartbeat. Infrastructure:

**Always-on daemon (launchd)** — `~/Library/LaunchAgents/com.user.aichat.gh-webhook.plist` (template committed at `fastlane/gh-webhook.plist.template`). Runs `smee-client` connecting to a smee.io channel, writes stdout+stderr to `/tmp/aichat-gh-events.log`. `RunAtLoad=true` + `KeepAlive=true` so it survives reboots and crashes.

**GitHub webhook** — registered once on `hanbin2007/AIChat`, events `issues|issue_comment|pull_request`, target URL = the smee channel. `config.content_type=json`.

**Monitor (per session)** — when a session starts the orchestrator:
1. Checks `launchctl list | grep aichat.gh-webhook` (launchd alive?).
2. Arms Monitor: `tail -n 0 -f /tmp/aichat-gh-events.log | grep --line-buffered -E "ECONNREFUSED 127.0.0.1:3000|EVENT "`. `persistent: true`. Each GitHub webhook delivery produces one new line in the log, which wakes the session and invokes `/tf-cycle`.
3. `ScheduleWakeup` 1800s — fallback heartbeat if Monitor ever misses (clock skew, smee dropout, etc.).

**Invariants**:
- Do not add a per-minute `CronCreate` — it'd just burn context and the Monitor already covers activity.
- Each tick re-queries GitHub via `gh` anyway (Phase 0 scans `updated:>=last_scan_iso`), so a missed Monitor event is recoverable at the next tick.
- The ECONNREFUSED line in the log is a *feature*, not a bug — the receiver-less setup means smee fails to POST to 127.0.0.1:3000, logs the error, and that error line is the signal. No HTTP server is required.

**Setup for a fresh machine** (one-time):
```
npm install -g smee-client
SMEE_URL=$(curl -sI https://smee.io/new | awk -F': ' '/^location:/ {print $2}' | tr -d '\r')
# Edit the template to bake SMEE_URL in, place under ~/Library/LaunchAgents/com.user.aichat.gh-webhook.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.aichat.gh-webhook.plist
gh api -X POST repos/hanbin2007/AIChat/hooks \
  -f name=web -F active=true \
  -f "events[]=issues" -f "events[]=issue_comment" -f "events[]=pull_request" \
  -f "config[url]=$SMEE_URL" -f "config[content_type]=json"
```

**Teardown**:
```
gh api -X DELETE repos/hanbin2007/AIChat/hooks/<HOOK_ID>   # id from `gh api /repos/...hooks`
launchctl bootout gui/$(id -u)/com.user.aichat.gh-webhook
rm ~/Library/LaunchAgents/com.user.aichat.gh-webhook.plist
```
