---
description: After an autofix PR merges, write TestFlight changelog and push main
trigger: GitHub event (pull_request closed+merged on main, head branch autofix/*, label auto-fix-ready)
---

You are the **SHIP** routine. Follow `_shared.md`. One run collects
every auto-fix-ready PR merged since `last_ship_iso`, writes the
changelog files, pushes to `main`, and waits for Xcode Cloud to
upload.

Xcode Cloud's `Ship to TestFlight` workflow is already configured to
run on every push to `main` and distribute to `PBTestGroup` — this
routine does **not** invoke any build tooling.

## Steps

1. **Load state.** Read `last_ship_iso` from the `meta-state` issue.

2. **Collect merged fix PRs.**
   ```
   gh pr list --repo hanbin2007/AIChat --state merged --label auto-fix-ready \
     --json number,title,mergedAt,headRefName,mergeCommit \
     --jq ".[] | select(.mergedAt > \"$LAST_SHIP_ISO\")"
   ```
   If empty: exit with `ship OK — no new fixes`. Do **not** touch
   WhatToTest files or push main when there's nothing to ship —
   Xcode Cloud would pick up a no-op ship run and burn compute.

3. **Build changelog bodies.** For each PR:
   - Linked issue: parse `Fixes #<N>` from the squash commit message
     (`git log -1 --format=%B <mergeCommit.oid>`).
   - `gh issue view <N> --json title,body`. Extract:
     - Feedback one-liner from the first blockquote in `## 原文`.
     - Summary: PR title with `fix(tf): ` prefix stripped.
   - zh-Hans block:
     ```
     修复 #<N>: <summary>
       反馈: "<feedback one-liner>"
     ```
   - en block:
     ```
     Fixes #<N>: <summary>
       Feedback: "<feedback one-liner>"
     ```

   Join blocks with blank lines. Cap each locale at 4000 chars
   (TF limit); drop the oldest blocks if over.

4. **Write + push.**
   ```
   git fetch origin main --quiet
   git checkout main
   git reset --hard origin/main
   printf '%s\n' "$ZH_BODY" > TestFlight/WhatToTest.zh-Hans.txt
   printf '%s\n' "$EN_BODY" > TestFlight/WhatToTest.en.txt
   git add TestFlight/WhatToTest.zh-Hans.txt TestFlight/WhatToTest.en.txt
   git commit -m "chore(tf): ship $(date -u +%Y%m%d-%H%M) — fixes <#N1,#N2,...>"
   git push origin main
   ```
   The push triggers Xcode Cloud's `Ship to TestFlight` workflow.

5. **Wait for upload.** Poll ASC for the latest Ship run:
   ```bash
   while true; do
     RUN=$(python3 .claude/routines/scripts/asc.py ship-latest \
             --workflow "$ASC_SHIP_WORKFLOW_ID")
     PROGRESS=$(echo "$RUN" | jq -r '.attributes.executionProgress')
     STATUS=$(echo   "$RUN" | jq -r '.attributes.completionStatus')
     RUN_NUMBER=$(echo "$RUN" | jq -r '.attributes.number')
     [ "$PROGRESS" = "COMPLETE" ] && break
     sleep 60
     # Exit before hitting routine timeout (~60 min). tf-sweep will
     # resume from here on its next hourly tick.
     [ "$SECONDS" -gt 3300 ] && {
       echo "ship DEFERRED — Xcode Cloud still running (run $RUN_NUMBER), handing off to tf-sweep"
       exit 0
     }
   done
   ```

   After the loop exits with `PROGRESS=COMPLETE`:
   - `STATUS == SUCCEEDED`: continue to step 6.
   - `STATUS in {FAILED, ERRORED, CANCELED}`: on each pending issue,
     comment
     `@hanbin2007 Ship FAILED on Xcode Cloud run <RUN_NUMBER>: <one line reason>. Details: <url>. Will retry next cycle.`
     Do **not** revert the main push. Exit with `ship FAILED`.

6. **Close out.** For each referenced issue:
   - `gh issue comment <N> --body "@hanbin2007 Shipped in TestFlight build <build_num> (Xcode Cloud run <runNumber>) to external group PBTestGroup."`
   - `gh issue edit <N> --add-label shipped-to-testflight`
   - `gh issue close <N>`
   - `gh pr edit <PR> --remove-label auto-fix-ready` (so we don't
     re-ship on the next sweep).

7. **Update state.** Set `last_ship_iso = now()` in `meta-state`.

## Summary line

`ship OK — shipped: <K> fixes, build <build_num>` or
`ship FAILED: <reason>`.

## Concurrency guard

Two `tf-ship` runs should never be in flight at once. Before step 4:
```bash
PREV=$(python3 .claude/routines/scripts/asc.py ship-latest \
         --workflow "$ASC_SHIP_WORKFLOW_ID" \
         | jq -r '.attributes.executionProgress')
if [ "$PREV" != "COMPLETE" ] && [ "$PREV" != "null" ]; then
  echo "ship DEFERRED — previous ship still uploading ($PREV)"
  exit 0
fi
```
The deferred work gets picked up on the next merged-PR event or by
`tf-sweep`.
