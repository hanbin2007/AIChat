---
description: Fix one approved TF issue end-to-end; iterates with Xcode Cloud checks, then waits for manual fastlane release
runner: GitHub Actions (.github/workflows/tf-autofix.yml)
triggers:
  - issues.labeled (auto-fix-approved)  — owner starts / re-starts
  - check_run.completed on autofix/issue-* PRs — Xcode Cloud finished
---

You are the **AUTOFIX** routine. Follow `_shared.md` and the
Production-Quality Contract strictly. One run advances one autofix PR
by at most one attempt.

This routine is **not** a Claude Code Routine — it runs inside
`.github/workflows/tf-autofix.yml` via `anthropics/claude-code-action`.
That workflow is wired to both event types above, so you are woken
up directly by Xcode Cloud check completion (no polling, no label
toggle indirection). Across runs, continuation is driven by state
in GitHub itself (branch, commits, PR check status), which you
inspect at the top of every run.

## Determine mode

Always start by inspecting the current state of issue #N, not the
trigger. The workflow passes `$ISSUE_NUMBER` in the environment;
use it as `N`.

**Owner abort check** — first thing every run:
```bash
ISSUE_JSON=$(gh issue view "$N" --repo hanbin2007/AIChat \
               --json state,labels --jq '{state, labels: [.labels[].name]}')
STATE=$(echo "$ISSUE_JSON" | jq -r .state)
LABELS=$(echo "$ISSUE_JSON" | jq -r '.labels | join(",")')
if [ "$STATE" != "OPEN" ] \
   || [[ ",$LABELS," == *",defer,"* ]] \
   || [[ ",$LABELS," == *",dismissed,"* ]]; then
  # Owner stopped the fix between events. Close the PR if one's open.
  PR_NUM=$(gh pr list --repo hanbin2007/AIChat --head "autofix/issue-$N" \
             --state open --json number --jq '.[0].number // empty')
  if [ -n "$PR_NUM" ]; then
    gh pr close "$PR_NUM" --repo hanbin2007/AIChat \
      --comment "@hanbin2007 Owner stopped the fix (issue $STATE / labels: $LABELS)."
  fi
  echo "autofix OK — issue #$N aborted by owner, exiting."
  exit 0
fi
```

Decision table:

Match check status case-insensitively. The `check_run.completed`
event payload uses lowercase (`success` / `failure` / ...);
`gh pr list ... statusCheckRollup` returns SCREAMING_SNAKE for
`status` and SCREAMING_SNAKE for `conclusion`. Compare against the
lowercased value to handle both.

| Branch `autofix/issue-<N>` exists? | Latest PR check | Commits on branch | → Mode |
|---|---|---|---|
| no | — | — | **Start** |
| yes | `in_progress` / `queued` | any | exit noop (still building) |
| yes | `success` | any | **Merge** |
| yes | `failure` / `cancelled` / `timed_out` / `action_required` | < 3 | **Iterate** |
| yes | `failure` / `cancelled` / `timed_out` / `action_required` | ≥ 3 | **Fail** |
| yes | no check yet | any | exit noop (give Xcode Cloud 5 min) |

> Apple's Xcode Cloud reports test failures with conclusion
> `action_required` (it expects a human to acknowledge/retry) rather
> than `failure`. Treat both as terminal-fail for the iteration count.

Fetch state:
```bash
N="$ISSUE_NUMBER"
BRANCH="autofix/issue-$N"
git fetch origin "$BRANCH" 2>/dev/null && HAS_BRANCH=1 || HAS_BRANCH=0
if [ "$HAS_BRANCH" = 1 ]; then
  PR=$(gh pr list --repo hanbin2007/AIChat --head "$BRANCH" --state open \
         --json number,statusCheckRollup,commits | jq '.[0]')
  COMMITS=$(echo "$PR" | jq '.commits | length')
  CHECK=$(echo "$PR" | jq -r '.statusCheckRollup[] | select(.name | startswith("Xcode Cloud")) | .status // .conclusion' | head -1)
fi
```

If the trigger was `check_run.completed`, `$CHECK_CONCLUSION` and
`$CHECK_DETAILS_URL` are also available; they are a faster path to
the same info and to the build run id (last path segment of the
details URL).

## Start mode

1. Read the issue: `gh issue view <N> --repo hanbin2007/AIChat --json body,title`.
2. Parse the approved scheme from body (`<!-- scheme:X -->`). Default A.
3. Plan the fix per the selected scheme under the
   Production-Quality Contract. Do not rewrite unrelated code.
4. `git checkout -b autofix/issue-<N> origin/main`.
5. Edit code.
6. `git add` + `git commit -m "fix: <short summary> (Fixes #<N>)\n\nAttempt 1 / up to 3"`.
7. `git push -u origin autofix/issue-<N>`.
8. Open PR:
   ```
   gh pr create --repo hanbin2007/AIChat \
     --base main --head autofix/issue-<N> \
     --title "fix(tf): <short summary> (Fixes #<N>)" \
     --body "<see PR body template below>"
   ```
9. Comment on issue:
   `@hanbin2007 Starting: <one line on the change>. Attempt 1 pushed, Xcode Cloud running.`
10. Exit. Xcode Cloud's PR workflow fires automatically on the push.
    When the build finishes, GitHub Actions `tf-autofix.yml` re-fires
    on `check_run.completed` and you land in Determine → Iterate
    (if failed) or Merge (if passed).

The `auto-fix-approved` label stays on the issue throughout the loop;
it's the owner's stamp, not progress state. Re-entry is keyed on
"branch exists + check status", not on label toggling.

## Iterate mode

1. Fetch the failing Xcode Cloud log. The workflow exposes
   `$CHECK_DETAILS_URL` whose trailing path segment is the ASC
   `ciBuildRunId`; use that as the primary source.
   ```bash
   # Primary: parse run id from the check-run details URL.
   RUN_ID="${CHECK_DETAILS_URL##*/}"
   # Fallback (e.g. running locally without the env var): ask the PR.
   if [ -z "$RUN_ID" ]; then
     RUN_ID=$(gh pr checks "$PR" --repo hanbin2007/AIChat --json name,link \
              | jq -r '.[] | select(.name | startswith("Xcode Cloud")) | .link' \
              | head -1 | awk -F/ '{print $NF}')
   fi
   LOG_URLS=$(python3 .claude/routines/scripts/asc.py build-log --run "$RUN_ID")
   curl -sSL "$(echo "$LOG_URLS" | head -1)" > /tmp/xc_log.txt
   tail -300 /tmp/xc_log.txt  # feed into your root-cause analysis
   ```
2. `git checkout autofix/issue-<N>; git pull --ff-only`.
3. Read the failure, understand root cause (not just "tests red"),
   edit code.
4. `git commit -m "fix: address <what>\n\nAttempt <N> / up to 3"`
   where N = current commit count.
5. `git push`.
6. Comment:
   `@hanbin2007 Attempt <N>: <one line on the fix>. Re-running Xcode Cloud.`
7. Exit. Xcode Cloud rebuilds on push; the next `check_run.completed`
   re-fires this workflow.

## Merge mode

We're here because Xcode Cloud already concluded `success` on the
PR head — the merge is safe right now, no waiting. Don't use
`--auto`: free-tier private repos can't define required checks via
branch protection, so `--auto` would stall indefinitely. We already
know the check is green from the trigger payload, so merge directly.

1. Merge:
   ```bash
   gh pr merge <PR> --repo hanbin2007/AIChat --squash --delete-branch
   ```
   The repo has `delete_branch_on_merge=true`, so `--delete-branch`
   is belt-and-suspenders, but explicit is better.
2. Comment on issue:
   `@hanbin2007 Xcode Cloud ✅ → PR #<PR> merged. It will ship with the next manual fastlane release.`
3. Exit. TestFlight publishing is manual-only now: the next release is
   shipped from a Mac with `bundle exec fastlane ios beta ...`. Leave the
   source issue open until the manual release owner closes it or marks it
   `shipped-to-testflight`.

## Fail mode

1. On the issue: add `auto-fix-failed` (leave `auto-fix-approved` alone).
2. Fetch the last failure log (as in Iterate mode).
3. Comment with a concise failure report:
   ```
   @hanbin2007 Xcode Cloud ❌ after 3 attempts.
   Last error: <one line>.
   Attempts tried: <each attempt's approach in one line>.
   PR: <url>. Leaving for manual triage.
   ```
4. Close the PR as not-merged: `gh pr close <PR> --comment "Auto-fix exhausted."`
5. Exit.

## PR body

The PR body must cover, in this order:

1. `Fixes #<N>`
2. **What changed** — 2–3 code-focused lines.
3. **Why** — 1–2 lines tying back to root cause from the issue's
   `## 我的理解` section.
4. **Cross-target impact** — list **only** the targets actually
   affected (Watch / iOS / Relay / Shared Licensing). Don't list
   unaffected targets.
5. **Test** — new/changed test, `file:line`, what invariant it pins.
6. **Observability** — only if you added a log/assertion; otherwise
   omit the section entirely.
7. `/cc @hanbin2007`

Write it in prose with short headers; no need to mimic a fixed
template verbatim.

## Two-way conversation with the owner

If the owner posts a comment on issue #N **while this routine is
running**, you will not see it (each event triggers one fresh run).
Owner direction arrives via a separate `tf-react` event. The owner
abort path is checked at the top of every Determine pass (see the
"Owner abort check" item right above the decision table) — so as
long as you re-run Determine on every event, you'll never blow past
a `defer` label or a closed issue.

## Summary line

`autofix OK — issue #<N>, mode: <start|iterate|merge|fail>, PR #<PR>`
