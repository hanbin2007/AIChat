# Routines — cloud-hosted tf-cycle

This directory replaces the old local-Mac `/tf-cycle` loop. Each file
is the prompt for one Claude Code Routine hosted on Anthropic
infrastructure. There is no always-on daemon; every run is triggered
by a GitHub webhook or a schedule.

See `docs/manual-fastlane-release.md` for the manual TestFlight release
runbook. This file covers the feedback/autofix Routines side.

## Topology

One prompt runs as a Claude Code Routine (cloud-hosted,
schedule-triggered). The other two — `tf-react` and `tf-autofix` — run
as GitHub Actions workflows because they need events Routines does not
expose: `issue_comment` (react) and `check_run.completed` (autofix).

| File | Runner | Trigger | Purpose |
|---|---|---|---|
| `tf-triage.md` | Routine | Schedule: hourly (`0 * * * *` — Routines minimum) | Pull new TF feedback → file issues |
| `tf-react.md`  | **GitHub Actions** (`.github/workflows/tf-react.yml`) | `issues.labeled` / `issues.closed` / `issue_comment.created` filtered by owner + `source:testflight-api` label | Process owner approvals / refinements |
| `tf-autofix.md` | **GitHub Actions** (`.github/workflows/tf-autofix.yml`) | `issues.labeled` (`auto-fix-approved`) + `check_run.completed` on `autofix/issue-*` branches | Start, iterate, merge one fix |

`_shared.md` is not a runnable prompt — it's prepended to every
prompt above. The Routines deployment pastes it at the top of each
routine in the web UI; the Actions workflows concatenate it with
the routine file in their "Assemble prompt" step.

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

3. **Find the Xcode Cloud product id** if you keep Xcode Cloud PR checks
   for autofix branches. Run this locally or from a scratch routine:
   ```bash
   export ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_PRIVATE_KEY="$(cat AuthKey_*.p8)"
   python3 .claude/routines/scripts/asc.py get "/v1/ciProducts?filter[app]=6760607040" \
     | jq '.data[] | {id, name: .attributes.name}'
   # → note the product id

   ```

4. **Create the routine** at claude.ai/code/routines (`tf-triage`):
   - Paste `_shared.md` content at the top of the prompt.
   - Append the routine file's content below.
   - Set the trigger per the table above.
   - Attach the built-in GitHub MCP connector.

   `tf-react` and `tf-autofix` are **not** created here — they run from
   `.github/workflows/`. Install the Claude GitHub App on the repo by
   running `/install-github-app` from Claude Code; that step also writes
   a `CLAUDE_CODE_OAUTH_TOKEN` repo secret (no Anthropic API key needed
   — it bills against your Claude subscription). The remaining secrets
   in step 5 must also be set on the repo (Settings → Secrets and
   variables → Actions), not just on the routine.

5. **Configure env vars / secrets.** Mark all ASC vars secret in the
   Routines UI; in GitHub put them under repo Actions secrets.

   | Var | Set on | Value |
   |---|---|---|
   | `CLAUDE_CODE_OAUTH_TOKEN` | GitHub repo secrets | for the Actions workflows — run `/install-github-app` in Claude Code to mint one (uses your Claude subscription, no API key) |
   | `ASC_KEY_ID` | all routines + repo secrets | from step 2 |
   | `ASC_ISSUER_ID` | all routines + repo secrets | from step 2 |
   | `ASC_PRIVATE_KEY` | all routines + repo secrets | full `.p8` PEM contents |
   | `ASC_PRODUCT_ID` | `tf-autofix` (repo secrets) | from step 3 |

   `ASC_APP_ID` (`6760607040`) is baked into `asc.py` as `DEFAULT_APP_ID`
   and does not need to be set as a secret. Only override via env var
   if you fork this for a different app.

6. **Seed the `meta-state` issue** (the first `tf-triage` run will
   create it if missing; you can do it by hand too):
   ```bash
   gh label create meta-state --color c5def5 --description "Routine state carrier"
   gh issue create --title "[meta] tf-cycle state — do not close" \
                   --label meta-state \
                   --body '{"last_feedback_iso":"1970-01-01T00:00:00Z","last_ship_iso":"1970-01-01T00:00:00Z"}'
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
| `asc.py build-log --run <id>` | Log download URLs for a failed run | `tf-autofix` (iterate) |

Dependencies: `pyjwt` + `cryptography`. `asc.py` auto-pip-installs
them on first run if missing, so you don't need a pre-baked image.

## Why some routines live in GitHub Actions

Claude Code Routines, on the current tier, supports `pull_request`,
`issues`, and `release` events plus `schedule`. It does **not** expose:

- `issue_comment` — the most ergonomic owner reply path (typing
  `approve A` in a comment). Without it, only label changes / closures
  are observable, which is fine for autofix gating but kills the
  comment-driven react flow.
- `check_run` / `workflow_run` / `check_suite` — the signal Xcode Cloud
  emits when a build finishes. Without it, the autofix loop has no
  native way to wake on cloud build outcomes.

GitHub Actions receives all of these with sub-minute latency, so the
prompts that need them (`tf-react`, `tf-autofix`) run there instead.
Each Action assembles `_shared.md` + the routine prompt at job-start
time and invokes
[anthropics/claude-code-action](https://github.com/anthropics/claude-code-action)
with the pre-minted `CLAUDE_CODE_OAUTH_TOKEN`. No polling daemon,
no label-toggle indirection.

## Migration from the old local orchestrator

The old `.claude/commands/tf-cycle.md` is now a pointer stub. Once
these routines are live and have processed at least one full issue
end-to-end (TF feedback → autofix), you can:

1. `launchctl bootout gui/$(id -u)/com.user.aichat.gh-webhook` on
   the Mac (if it's still around)
2. Delete the smee channel
3. Use `fastlane/Fastfile` + `fastlane/.env` locally as the only
   TestFlight publishing path.

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
