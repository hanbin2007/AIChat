---
description: After an autofix PR merges, write TestFlight changelog and push main
trigger: GitHub event (pull_request closed+merged on main, head branch autofix/*, label auto-fix-ready)
---

You are the **SHIP** routine. Follow `_shared.md`. One run collects
every `auto-fix-ready` PR merged since `last_ship_iso`, writes the
changelog files, and pushes `main`. **You do not wait for Xcode
Cloud to finish.**

After `main` is pushed, Xcode Cloud's `Ship to TestFlight` workflow
runs and reports its conclusion as a `check_run` on the new `main`
commit. The companion workflow `.github/workflows/tf-ship-finalize.yml`
listens for that `check_run.completed` event and handles closing the
issues + label cleanup. That keeps this routine quick (no 60-min
polling, no concurrency-guard incantation).

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

   # Embed the issue numbers in the commit message so tf-ship-finalize
   # can match this push back to the issues that need closing without
   # a second query.
   ISSUE_LIST="$(printf '#%s ' $ISSUE_NUMBERS)"   # e.g. "#42 #51 "
   git commit -m "chore(tf): ship $(date -u +%Y%m%d-%H%M) — fixes ${ISSUE_LIST% }"
   git push origin main
   ```

5. **Update state.** Set `last_ship_iso = now()` in `meta-state`.

That's it — no polling, no `--remove-label` step, no Xcode Cloud
status check. `tf-ship-finalize.yml` handles everything that depends
on the cloud upload result.

## Summary line

`ship OK — pushed: <K> fixes (PRs <#N1,#N2,...>), main commit <sha>`
or `ship FAILED: <reason>` (only used for pre-push failures — git
problems, state-issue write errors, etc).
