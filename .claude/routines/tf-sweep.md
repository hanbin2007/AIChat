---
description: Hourly fallback that catches missed webhook events
trigger: schedule (every 1 hour)
---

You are the **SWEEP** routine. Follow `_shared.md`. One run re-runs
the event-driven phases against current GitHub state so nothing
stays stuck if a webhook was dropped, rate-limited, or delivered
during a Routines outage.

This routine does **not** do investigation, approval, or code
editing. It only notices state that looks wrong and nudges it.

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

2. **Dropped PR sync events.**
   - List open PRs with head `autofix/issue-*` whose last push is
     >15 min old:
     ```
     gh pr list --repo hanbin2007/AIChat --state open \
       --search "head:autofix/ sort:updated-desc" \
       --json number,headRefName,updatedAt,statusCheckRollup
     ```
   - For each: look at the Xcode Cloud check. If status is SUCCESS
     and the PR is not yet merged (no `auto-merge` queued), or if
     status is FAILURE and the branch still has <3 commits and no
     new commit in >15 min → re-dispatch:
     ```
     gh pr comment <PR> --body "<!-- sweep: poke autofix -->"
     ```
     The comment triggers a PR sync event which `tf-autofix` picks
     up in CONTINUE mode.

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
