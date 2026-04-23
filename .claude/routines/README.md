# Routines — cloud-hosted tf-cycle

This directory replaces the old local-Mac `/tf-cycle` loop. Each file
is the prompt for one Claude Code Routine hosted on Anthropic
infrastructure. There is no always-on daemon; every run is triggered
by a GitHub webhook or a schedule.

See `docs/xcode-cloud.md` for the Xcode Cloud side (build + TestFlight
upload). This file covers the Routines side.

## Routines to create

| File | Trigger | Purpose |
|---|---|---|
| `tf-triage.md` | Schedule: every 30 min | Pull new TF feedback → file issues |
| `tf-react.md` | GitHub `issues` / `issue_comment` with label `source:testflight-api` | Process owner approvals / refinements |
| `tf-autofix.md` | GitHub `issues` (labeled `auto-fix-approved`) **AND** `pull_request` sync on `autofix/*` | Start, iterate, merge one fix |
| `tf-ship.md` | GitHub `pull_request` closed + merged with label `auto-fix-ready` | Write WhatToTest → push main → wait for upload |
| `tf-sweep.md` | Schedule: every 1 hour | Fallback for dropped webhooks |

`_shared.md` is not a routine — it's included in every routine's
deployed prompt (paste at the top in the web UI, or `@include` it if
supported).

## One-time setup

1. **Install the Claude GitHub App** on `hanbin2007/AIChat` from
   claude.com settings.

2. **Generate an App Store Connect API key.** In ASC → Users and
   Access → Integrations → App Store Connect API → `+`. Role: Admin.
   - Copy the **Key ID** (10 chars).
   - Copy the **Issuer ID** (UUID) from the top of the page.
   - Download the `.p8` file — you only get it **once**. Keep the
     full file contents (including the `BEGIN`/`END` lines) for the
     `ASC_PRIVATE_KEY` env var.

3. **Find the Xcode Cloud product + ship workflow ids.** Once you've
   set up Xcode Cloud (see `docs/xcode-cloud.md`), run these locally
   or from a scratch routine:
   ```bash
   export ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_PRIVATE_KEY="$(cat AuthKey_*.p8)"
   python3 .claude/routines/scripts/asc.py get "/v1/ciProducts?filter[app]=6760607040" \
     | jq '.data[] | {id, name: .attributes.name}'
   # → note the product id

   python3 .claude/routines/scripts/asc.py get "/v1/ciProducts/<PRODUCT_ID>/workflows" \
     | jq '.data[] | {id, name: .attributes.name}'
   # → note the "Ship to TestFlight" workflow id
   ```

4. **Create the 5 routines** at claude.ai/code/routines. For each:
   - Paste `_shared.md` content at the top of the prompt.
   - Append the routine file's content below.
   - Set the trigger per the table above.
   - Attach the built-in GitHub MCP connector.

5. **Configure env vars** on each routine (Settings → Environment).
   Mark all ASC vars secret:

   | Var | Set on | Value |
   |---|---|---|
   | `ASC_KEY_ID` | all | from step 2 |
   | `ASC_ISSUER_ID` | all | from step 2 |
   | `ASC_PRIVATE_KEY` | all | full `.p8` PEM contents |
   | `ASC_APP_ID` | `tf-triage` | `6760607040` |
   | `ASC_PRODUCT_ID` | `tf-autofix`, `tf-ship`, `tf-sweep` | from step 3 |
   | `ASC_SHIP_WORKFLOW_ID` | `tf-ship`, `tf-sweep` | from step 3 |

6. **Seed the `meta-state` issue** (the first `tf-triage` run will
   create it if missing; you can do it by hand too):
   ```bash
   gh label create meta-state --color c5def5 --description "Routine state carrier"
   gh issue create --title "[meta] tf-cycle state — do not close" \
                   --label meta-state \
                   --body '{"last_feedback_iso":"1970-01-01T00:00:00Z","last_triage_iso":"1970-01-01T00:00:00Z","last_ship_iso":"1970-01-01T00:00:00Z"}'
   gh issue pin <N>
   ```

## ASC API access

All Apple-side calls go through `.claude/routines/scripts/asc.py`.
It mints a short-lived ES256 JWT on every call (Apple's auth model
requires this — static tokens aren't supported).

Subcommands:

| Command | Purpose | Used by |
|---|---|---|
| `asc.py jwt` | Print a fresh JWT (debug) | — |
| `asc.py get <path>` | GET any ASC endpoint, print JSON | ad-hoc |
| `asc.py feedback --since <iso>` | Normalized TF feedback list | `tf-triage` |
| `asc.py ship-latest --workflow <id>` | Latest Xcode Cloud run for a workflow | `tf-ship`, `tf-sweep` |
| `asc.py build-log --run <id>` | Log download URLs for a failed run | `tf-autofix` (iterate) |

For one-shot `curl`-style access from bash:
```bash
source .claude/routines/scripts/asc_helpers.sh
asc_get /v1/ciBuildRuns/<id>
```

Dependencies: `pyjwt` + `cryptography`. `asc.py` auto-pip-installs
them on first run if missing, so you don't need a pre-baked image.

## Event coverage caveat

As of this writing, Claude Code Routines supports `pull_request`,
`issues`, `issue_comment`, and `release` events, with label filters
for `issues`. If your Routines tier doesn't fire on `issues` with
label filters, `tf-sweep` at hourly cadence is the safety net — it
re-checks state and forcibly re-dispatches by toggling labels.

Do **not** rely on `workflow_run` or `check_run` events (Xcode Cloud
posts status via the GitHub app, which shows up as a PR sync — that
is what `tf-autofix` continuation listens to).

## Migration from the old local orchestrator

The old `.claude/commands/tf-cycle.md` is now a pointer stub. Once
these routines are live and have processed at least one full issue
end-to-end (TF feedback → autofix → ship), you can:

1. `launchctl bootout gui/$(id -u)/com.user.aichat.gh-webhook` on
   the Mac (if it's still around)
2. Delete the smee channel
3. Keep `fastlane/Fastfile` + `fastlane/.env` locally as a manual
   emergency-ship escape hatch. The `fastlane/nightly.sh` launchd
   job can be removed entirely — nothing references it anymore.

The `meta-state` issue replaces `tf-state.json`. The smee log
(`/tmp/aichat-gh-events.log`) is no longer consulted by any routine
— webhooks go directly from GitHub to the Claude GitHub App.

## Why we dropped the testflight-feedback MCP

Earlier drafts of these routines called `mcp__testflight-feedback__list_feedback`.
That server ran on the user's local Mac (stdio transport via
`claude mcp add`) and is unreachable from Anthropic's Routines
sandbox. Re-hosting it as a public HTTPS MCP would add a service to
maintain; since the server was just a thin wrapper around the ASC
REST API anyway, `asc.py feedback` is the direct replacement with
one fewer moving part.
