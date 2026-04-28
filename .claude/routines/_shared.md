# Shared context for tf-cycle routines

Every routine under `.claude/routines/` must follow this file. It is
pasted into each routine prompt at deployment time, or referenced from
the routine content when the web UI supports `@include`.

## Repo constants

- GitHub repo: `hanbin2007/AIChat`
- ASC app id: `6760607040`
- App bundle: `hanbin.AIChat`
- External TF group: `PBTestGroup`
- Default branch: `main`

## Production-Quality Contract

Every fix must hold to these. Surface-level patches that only silence
the immediate symptom are not acceptable.

1. **Root cause, not symptom.** Trace why the bug happens, which
   invariant got violated, which state transition was unguarded.
2. **Cross-target audit.** AIChat has four targets: `AIChat Watch App`
   (watchOS primary), `AIChat iOS App` (companion), `AIChat Relay`
   (macOS), `Shared Licensing` (cross-platform). Any shared code
   change is verified against every target that compiles it — the
   Xcode Cloud `PR Build & Test` workflow builds all three app
   targets. UI work must call out 46mm watch sizing + Digital Crown.
3. **Concurrency / failure paths.** Call out `@MainActor` boundaries,
   `Task` lifetimes, async re-entrancy, cancellation, cold launch,
   low memory, bg→fg, iCloud latency, network timeout, empty input,
   storage corruption.
4. **Tests pin the invariant.** watchOS 26 tests must be
   `async throws` even if synchronous. Tests are a means, not the
   end — if an existing test is itself buggy, edit or delete it and
   explain in the commit message.
5. **No dead code.** No commented-out blocks, no unused feature flags,
   no half-refactors.
6. **Observability when failure was invisible.** If the user saw a
   silent bad state, consider adding a log or assertion.
7. **Security.** Never widen token/key access, never log secrets,
   never trust relay client input on the server side.

## Persistent state (the state issue)

There is no more `tf-state.json`. The persistent cursor lives in a
pinned GitHub issue labeled `meta-state`, title
`[meta] tf-cycle state — do not close`. Its body is JSON:

```json
{
  "last_feedback_iso": "2026-04-23T00:00:00Z",
  "last_ship_iso":     "2026-04-23T00:00:00Z",
  "processed_feedback_ids": ["ALszOk...", "..."]
}
```

`processed_feedback_ids` is an ID-level guard for `tf-triage`: a
FIFO-trimmed list (cap 200) of ASC submission ids that have already
been seen. It exists because the `[hash:<12>]` title search has
historically missed duplicates and the `last_feedback_iso` cursor
alone isn't strict enough — late-arriving items inside the same
30-min poll window slipped through and got refiled.

**Read**:
```
STATE_ISSUE=$(gh issue list --repo hanbin2007/AIChat --label meta-state --state open --json number -q '.[0].number')
STATE=$(gh issue view "$STATE_ISSUE" --repo hanbin2007/AIChat --json body -q .body)
```

**Write**: mutate via `jq`, then:
```
gh issue edit "$STATE_ISSUE" --repo hanbin2007/AIChat --body "$NEW_STATE"
```

If no `meta-state` issue exists yet, create one:
```
gh issue create --repo hanbin2007/AIChat \
  --title "[meta] tf-cycle state — do not close" \
  --label meta-state \
  --body '{"last_feedback_iso":"1970-01-01T00:00:00Z","last_ship_iso":"1970-01-01T00:00:00Z"}'
```

## App Store Connect API access (shared by most routines)

All Apple-side calls (TF feedback, Xcode Cloud build status, build
logs) go through `.claude/routines/scripts/asc.py` — a Python helper
that mints an ES256 JWT and wraps the REST API.

```bash
# Typical use from a routine:
python3 .claude/routines/scripts/asc.py feedback --since "$SINCE"
python3 .claude/routines/scripts/asc.py build-log --run "$RUN_ID"

# Ad-hoc GET (returns pretty JSON):
python3 .claude/routines/scripts/asc.py get "/v1/ciBuildRuns/$RUN_ID"
```

Required env vars / secrets on every job that calls ASC:
- `ASC_KEY_ID` — 10-char key id
- `ASC_ISSUER_ID` — issuer UUID
- `ASC_PRIVATE_KEY` — full PEM contents of the `.p8`, including
  `-----BEGIN PRIVATE KEY-----` / `-----END PRIVATE KEY-----`
- `ASC_PRODUCT_ID` — only on jobs that talk to Xcode Cloud

`ASC_APP_ID` is hardcoded in `asc.py` (`DEFAULT_APP_ID`); override with
the env var only if you fork this for a different app.

`ASC_BASE_URL` exists as an escape hatch for sandboxes that can't reach
`api.appstoreconnect.apple.com` directly — it points `asc.py` at the
relay's `/api/asc` proxy. GitHub-hosted runners reach Apple directly,
so leave it unset there.

## Per-fix state (no state file needed)

Everything else is derived from GitHub state directly — there is no
`in_flight` dict:

| Meaning | GitHub signal |
|---|---|
| Issue approved | issue label `auto-fix-approved` |
| Autofix in progress | open PR on `autofix/issue-<N>` branch |
| CI running | PR check `Xcode Cloud / PR Build & Test` status |
| Attempts used | commit count on the `autofix/issue-<N>` branch |
| Awaiting merge | PR label `auto-fix-ready` |
| Fix shipped | issue label `shipped-to-testflight`, issue `closed` |
| Failed, needs human | issue label `auto-fix-failed` |

## Owner pings

Every reply comment on an issue/PR **must start with `@hanbin2007 `**
so the owner gets the mobile push. Keep comments terse (<200 chars),
no code blocks except in the final SUCCESS/FAILED report.

## Labels used

- `source:testflight-api` — all issues created from TF
- `tf-bug` / `tf-feature` / `tf-other` — classification
- `needs-review` — awaiting owner approval
- `needs-fix` — bug that should be fixed
- `auto-fix-approved` — owner OK'd; on **issue**
- `auto-fix-ready` — Xcode Cloud passed, awaiting merge; on **PR**
- `auto-fix-failed` — 3 attempts exhausted or cloud rejected; on **issue**
- `shipped-to-testflight` — terminal success label
- `meta-state` — the persistent-state issue (never close)
- `dismissed` / `defer` / `regression` — misc
