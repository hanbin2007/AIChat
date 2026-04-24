---
description: 15-min tick that polls Xcode Cloud results and pokes stuck routines
trigger: schedule (every 15 minutes)
---

You are the **SWEEP** routine. Follow `_shared.md`. Two jobs:

1. **Primary (every tick): poll Xcode Cloud check results** on open
   autofix PRs and poke `tf-autofix` when a check has completed.
   This is necessary because this Routines tier does not expose
   `check_run` events, so `tf-autofix` cannot be event-triggered
   when Xcode Cloud finishes a build — sweep is how it finds out.

2. **Fallback: rescue dropped webhooks and stale state** elsewhere
   in the pipeline.

This routine does **not** do investigation, approval, or code
editing. It only observes state and nudges it.

## Steps

1. **Dropped owner reactions.**
   - List open issues updated in the last 2 hours with label
     `source:testflight-api`:
     ```
     gh issue list --repo hanbin2007/AIChat --state open \
       --label source:testflight-api \
       --search "updated:>=$(date -u -v-2H '+%Y-%m-%dT%H:%M:%SZ')" \
       --json number,labels,updatedAt
     ```
   - For each, check: does it have `auto-fix-approved` but no
     open `autofix/issue-<N>` branch, no open PR, and no
     `auto-fix-failed` label? → the `tf-autofix` start event was
     missed. Re-dispatch by removing and re-adding the label:
     ```
     gh issue edit <N> --remove-label auto-fix-approved
     gh issue edit <N> --add-label  auto-fix-approved
     ```
     (The label-add re-fires the `tf-autofix` routine.)

2. **Poll Xcode Cloud check results on every open autofix PR.** This
   is the primary job. For each open PR with head `autofix/issue-*`:
   ```bash
   gh pr list --repo hanbin2007/AIChat --state open \
     --search "head:autofix/" \
     --json number,headRefName,commits,statusCheckRollup,body,updatedAt
   ```
   Extract the Xcode Cloud check (name starts with `Xcode Cloud`).
   Note the issue number `N` from `headRefName` (`autofix/issue-<N>`)
   and the commit count on the branch.

   Decide by check state:

   | Check | Commits | Age of last commit | Action |
   |---|---|---|---|
   | `IN_PROGRESS` / `QUEUED` / `PENDING` | — | — | skip (still building) |
   | `SUCCESS` | — | — | skip (auto-merge will handle it; if PR is old and still unmerged, see step 3) |
   | `FAILURE` / `CANCELLED` / `TIMED_OUT` | < 3 | any | **poke autofix** |
   | `FAILURE` / `CANCELLED` / `TIMED_OUT` | ≥ 3 | any | **poke autofix** (it will go to Fail mode and clean up) |
   | no check yet | — | > 10 min | **poke autofix** (Xcode Cloud failed to trigger) |
   | no check yet | — | ≤ 10 min | skip (give Xcode Cloud time) |

   "poke autofix" = toggle the `auto-fix-approved` label on the
   linked issue, which re-fires `tf-autofix`:
   ```bash
   gh issue edit $N --repo hanbin2007/AIChat --remove-label auto-fix-approved
   # one-shot; no sleep needed — the removal doesn't fire autofix
   gh issue edit $N --repo hanbin2007/AIChat --add-label    auto-fix-approved
   ```
   Only the **add** fires the routine (trigger filter is
   `labeled`). Do not also add a comment — comments are noise and
   don't trigger tf-autofix anyway.

   Before poking, check you haven't already poked in the last 10 min
   (look for the last `auto-fix-approved` label event via
   `gh api /repos/.../issues/$N/events`). If so, skip to avoid
   storms when Xcode Cloud is genuinely slow.

3. **Stuck ship.**
   - If there is any merged PR with label `auto-fix-ready` older
     than 1 hour (i.e. `tf-ship` should have closed it by now),
     re-fire ship:
     ```
     # Touch a tiny no-op on main to retrigger the ship event flow
     # Actually: just run ship logic inline here.
     ```
     Read `tf-ship.md` and perform steps 1-7 inline. If the last
     Xcode Cloud ship run is still in progress, defer.

4. **Orphaned meta-state.**
   - If no `meta-state` issue exists: create it (see `_shared.md`).

5. **Stale `auto-fix-in-progress`.**
   - Any issue with `auto-fix-in-progress` but no open PR and no
     branch → clear the label, add `auto-fix-failed`, comment
     `@hanbin2007 Autofix state lost (branch gone). Please re-approve if still wanted.`.

## Summary line

`sweep OK — rescued: <K> (nudged_autofix: <a>, nudged_pr: <b>, rescued_ship: <c>, cleaned_stale: <d>)`

## Safety

- Never create new issues, never edit code, never open PRs.
- Never revert or force-push.
- Sweep is idempotent — if there's nothing to do, exit quietly.
