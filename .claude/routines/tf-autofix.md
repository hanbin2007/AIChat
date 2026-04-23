---
description: Fix one approved TF issue end-to-end; iterates with Xcode Cloud
trigger: GitHub event (issues labeled auto-fix-approved) OR pull_request sync on autofix/* branches
---

You are the **AUTOFIX** routine. Follow `_shared.md` and the
Production-Quality Contract strictly. One run advances one autofix PR
by at most one attempt. Continuation across runs is driven by the
branch's commit count and the latest PR check status.

## Determine mode

Inspect the trigger:

- **Label event `auto-fix-approved` added on issue #N:** this is a
  **START**. There is no `autofix/issue-<N>` branch yet. Go to
  `## Start mode`.

- **PR sync event on `autofix/issue-<N>`:** this is a **CONTINUE**.
  Check the latest `Xcode Cloud / PR Build & Test` check on the PR:
  - `IN_PROGRESS` / `QUEUED` → exit (next sync event will re-enter).
  - `SUCCESS` → go to `## Merge mode`.
  - `FAILURE` / `CANCELLED`:
    - If branch has <3 commits → go to `## Iterate mode`.
    - If branch has ≥3 commits → go to `## Fail mode`.

- Any other trigger → exit noop.

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
11. Exit. Xcode Cloud's PR workflow fires automatically. When it
    finishes, GitHub posts a check; the PR sync event re-enters this
    routine in CONTINUE mode.

## Iterate mode

1. Fetch the failing Xcode Cloud log. Mint an ASC JWT from workflow
   env vars `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_PRIVATE_KEY`
   (see `.claude/routines/README.md` for the helper snippet), then:
   ```
   GET /v1/ciBuildRuns?filter[product]=<PROD_ID>&filter[pullRequest]=<PR_NUM>&sort=-createdDate&limit=1
   GET /v1/ciBuildRuns/{id}/actions
   GET /v1/ciBuildActions/{id}/artifacts
   ```
   Download the log artifact and grep the failure.
2. `git checkout autofix/issue-<N>; git pull --ff-only`.
3. Read the failure, understand root cause (not just "tests red"),
   edit code.
4. `git commit -m "fix: address <what>\n\nAttempt <N> / up to 3"`
   where N = current commit count.
5. `git push`.
6. Comment:
   `@hanbin2007 Attempt <N>: <one line on the fix>. Re-running Xcode Cloud.`
7. Exit.

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
