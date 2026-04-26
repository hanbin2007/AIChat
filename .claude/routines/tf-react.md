---
description: Process owner reactions on TF issues
trigger: GitHub Actions (.github/workflows/tf-react.yml) — issues / issue_comment, owner-only, source:testflight-api
---

You are the **REACT** routine. Follow `_shared.md`. One run processes
one owner interaction (comment or label change) on one TF issue.

This prompt runs from `tf-react.yml` (not Routines — Routines does not
expose `issue_comment`). The workflow has already filtered on
owner-sender + `source:testflight-api` label, so you can act
unconditionally on these env vars:

- `$EVENT_NAME` — `issues` or `issue_comment`
- `$EVENT_ACTION` — `labeled` / `closed` for issues, `created` for issue_comment
- `$ISSUE_NUMBER` — issue to operate on
- `$LABEL_NAME` — populated only for `issues.labeled`
- `$COMMENT_BODY` — populated only for `issue_comment.created`
- `$ACTOR` — sender login (always the repo owner; pre-filtered)

## Steps

1. **Fetch issue.** `gh issue view <N> --repo hanbin2007/AIChat --json body,comments,labels,state,title`.

2. **Determine intent.**

   **For `issue_comment` events (owner posted a new comment):**
   - Body contains `approve` (case-insensitive) + optional scheme
     letter `A`/`B`/`C`/`D` → add label `auto-fix-approved`. Append
     `<!-- scheme:X -->` to the issue body via
     `gh issue edit --body`. This label add will trigger the
     `tf-autofix` routine; nothing more to do here.
   - Body contains `defer` → add label `defer`, remove `needs-fix` /
     `needs-review`. Done.
   - Body contains `dismiss` → `gh issue close <N>` with label
     `dismissed`. Done.
   - Anything else → treat as refinement: read the comment carefully,
     edit the issue body to update `## 我的理解` / `## 建议方案` per
     their guidance, post
     `@hanbin2007 Got it. Updated plan: <1-2 sentence summary>. Reply \`approve A\` to proceed or comment further.`
     Keep `needs-review` label.

   **For `issues` events with `action == labeled`:**
   - Label added was `auto-fix-approved` → ok, let the autofix
     routine pick it up. Exit.
   - Label added was `defer` / `regression` / others → no-op, exit.

   **For `issues` events with `action == closed`:**
   - If issue has no `shipped-to-testflight` label → treat as
     dismissed, add `dismissed` if missing. Done.

3. **Always** end with a summary line:
   `react OK — issue #<N>, intent: <approve|defer|dismiss|refine|noop>`.

## Invariants

- The workflow already filtered out non-owner senders, non-TF issues,
  and the `meta-state` issue. You can trust the inputs.
- The `auto-fix-approved` label-add path is owned by `tf-autofix.yml`;
  the workflow skips it for you. If your prompt sees that label_name
  anyway, exit-noop.
- Never double-process. GitHub may redeliver webhooks; be idempotent
  (e.g. skip adding a label that's already present, skip closing an
  already-closed issue).
