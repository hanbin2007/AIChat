---
description: Close issues + remove auto-fix-ready labels after Xcode Cloud uploads to TestFlight
runner: GitHub Actions (.github/workflows/tf-ship-finalize.yml)
trigger: check_run.completed on main with name matching "Xcode Cloud / Ship to TestFlight"
---

You are the **SHIP-FINALIZE** routine. Follow `_shared.md`. Wakes up
after Xcode Cloud reports the `Ship to TestFlight` check on a `main`
commit. Closes the issues that the merged ship-commit references and
removes the `auto-fix-ready` label from the corresponding PRs.

This is the second half of the ship leg, replacing the old in-routine
polling loop. The first half (`tf-ship`) writes WhatToTest and pushes
main — fast and synchronous. This half runs whenever Xcode Cloud is
done — minutes or hours later — without holding a routine open.

The workflow passes:
- `$MAIN_SHA` — the main commit Xcode Cloud just built
- `$CHECK_CONCLUSION` — `success` / `failure` / `cancelled` / `timed_out`
- `$CHECK_DETAILS_URL` — link to the cloud run for failure reports

## Steps

1. **Match the commit back to issues.** The `tf-ship` routine writes
   commit messages of the form
   `chore(tf): ship YYYYMMDD-HHMM — fixes #<N1> #<N2> ...`. Parse the
   issue numbers out:
   ```bash
   MSG=$(git log -1 --format=%B "$MAIN_SHA")
   ISSUES=$(echo "$MSG" | grep -oE '#[0-9]+' | tr -d '#')
   if [ -z "$ISSUES" ]; then
     echo "Not a tf-ship commit — exiting noop."
     exit 0
   fi
   ```

   Also collect the PRs that wear `auto-fix-ready` and were merged
   into this push:
   ```bash
   PRS=$(gh pr list --repo hanbin2007/AIChat \
           --state merged --label auto-fix-ready \
           --json number,mergeCommit,title \
           --jq ".[] | select(.mergeCommit.oid != \"$MAIN_SHA\") | .number")
   ```
   (PRs were merged before the ship commit; they show up as merged
   without being the ship commit itself.)

2. **Branch on `$CHECK_CONCLUSION`.**

   **`success`:** for each issue number in `$ISSUES`:
   - `gh issue comment <N> --body "@hanbin2007 Shipped in TestFlight build <build_num>. Xcode Cloud run <details_url>."`
   - `gh issue edit <N> --add-label shipped-to-testflight`
   - `gh issue close <N>`

   For each PR in `$PRS`:
   - `gh pr edit <PR> --remove-label auto-fix-ready`

   The TestFlight build number can be parsed from the cloud run via
   `python3 .claude/routines/scripts/asc.py get
   /v1/ciBuildRuns/<RUN_ID>` — `attributes.number` is the run #,
   `relationships.builds` resolves to the produced build. Optional;
   if it's noisy to fetch, just say "the latest TestFlight build".

   **`failure` / `cancelled` / `timed_out`:** for each issue:
   - `gh issue comment <N> --body "@hanbin2007 Ship FAILED on Xcode Cloud: $CHECK_DETAILS_URL. Will retry on the next push to main; the auto-fix-ready label stays so the next ship picks the PR up again."`

   Do **not** revert main, do **not** remove `auto-fix-ready` —
   the next legit `tf-ship` run will sweep these PRs back up.

   **anything else:** exit noop.

3. **Summary line.**
   `ship-finalize OK — issues: <N1,N2,...>, conclusion: <success|failure|...>`
