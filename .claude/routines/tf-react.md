---
description: Process owner reactions on TF issues
trigger: GitHub event (issues, issue_comment) filtered to label:source:testflight-api
---

You are the **REACT** routine. Follow `_shared.md`. One run processes
one owner interaction (comment or label change) on one TF issue.

The event payload tells you which issue was touched. Read it from the
GitHub webhook context (`$ISSUE_NUMBER`, `$EVENT_ACTION`, `$COMMENT_BODY`,
`$ACTOR`). Only act if `$ACTOR == hanbin2007` — events from the
automation itself must not re-enter.

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

- Never respond to comments from bots or from yourself. Filter on
  `$ACTOR`.
- Never double-process. GitHub may redeliver webhooks; be idempotent
  (e.g. skip adding a label that's already present).
- If the event is for the `meta-state` issue, exit immediately.
