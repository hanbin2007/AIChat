---
description: Fix one approved TF issue end-to-end; iterates with Xcode Cloud
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
use it as `N`. Decision table:

| Branch `autofix/issue-<N>` exists? | Latest PR check | Commits on branch | → Mode |
|---|---|---|---|
| no | — | — | **Start** |
| yes | `IN_PROGRESS` / `QUEUED` | any | exit noop (still building) |
| yes | `SUCCESS` | any | **Merge** |
| yes | `FAILURE` / `CANCELLED` / `TIMED_OUT` | < 3 | **Iterate** |
| yes | `FAILURE` / `CANCELLED` / `TIMED_OUT` | ≥ 3 | **Fail** |
| yes | no check yet | any | exit noop (give Xcode Cloud 5 min) |

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
9. Swap labels on issue #N: remove `auto-fix-approved`, add
   `auto-fix-in-progress`.
10. Comment on issue:
    `@hanbin2007 Starting: <one line on the change>. Attempt 1 pushed, Xcode Cloud running.`
11. Exit. Xcode Cloud's PR workflow fires automatically on the push.
    When the build finishes, GitHub Actions `tf-autofix.yml` re-fires
    on `check_run.completed` and you land in Determine → Iterate
    (if failed) or Merge (if passed).

## Iterate mode

1. Fetch the failing Xcode Cloud log. Use `asc.py`:
   ```bash
   source .claude/routines/scripts/asc_helpers.sh
   # Find the latest build run for this PR's branch
   RUN_ID=$(asc_get "/v1/ciProducts/$ASC_PRODUCT_ID/buildRuns?sort=-createdDate&limit=20" \
            | jq -r --arg br "autofix/issue-$N" \
                '.data[] | select(.attributes.sourceCommit.commitSha != null) | select(.relationships.sourceBranchOrTag.data != null) | .id' \
            | head -1)
   # If filter-by-branch isn't available on your Apple plan, fall back:
   #   check the PR's check-run details URL — the trailing path segment
   #   is the ciBuildRunId:
   #   gh pr checks <PR> --json name,link | jq -r '.[] | select(.name | startswith("Xcode Cloud")) | .link'
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

1. `gh pr merge <PR> --repo hanbin2007/AIChat --squash --auto`.
2. On the issue: remove `auto-fix-in-progress`, add `auto-fix-ready`.
3. Comment on issue:
   `@hanbin2007 Xcode Cloud ✅ → PR #<PR> queued for merge.`
4. Exit. The `pull_request closed+merged` event will fire
   `tf-ship` later.

## Fail mode

1. On the issue: remove `auto-fix-in-progress`, add `auto-fix-failed`.
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

## PR body template

```
Fixes #<N>

## What changed
<2-3 lines, code-focused>

## Why
<1-2 lines linking to the root cause from the issue's 我的理解 section>

## Cross-target impact
- AIChat Watch App: <rebuild yes/no, what to verify>
- AIChat iOS App:   <...>
- AIChat Relay:     <...>
- Shared Licensing: <...>

## Test
<new or changed test file:line; what invariant it pins>

## Observability
<new log or assertion; or "n/a — failure was already visible">

/cc @hanbin2007
```

## Two-way conversation with the owner

If the owner posts a comment on issue #N **while this routine is
running**, you will not see it (routines are event-bound). Owner
direction arrives as a separate `tf-react` event. If that event sets
label `defer` or closes the issue, the `tf-autofix` continuation
path's first check should be: is the issue still open and not
deferred? If not → `gh pr close <PR> --comment "Owner stopped the fix."`
and exit. Add this check as step 0 of both Iterate and Merge modes.

## Summary line

`autofix OK — issue #<N>, mode: <start|iterate|merge|fail>, PR #<PR>`
