---
description: DEPRECATED — see .claude/routines/ for the cloud-hosted version
---

The always-on local orchestrator is gone. The TestFlight feedback →
GitHub review → autofix → ship loop now runs as five independent
Claude Code Routines hosted on Anthropic infrastructure. Every run
is triggered by a GitHub webhook or a schedule; there is no daemon.

See `.claude/routines/README.md` for the full architecture and
deployment steps. The routines are:

| File | Trigger | Purpose |
|---|---|---|
| `.claude/routines/tf-triage.md` | Schedule 30 min | Pull TF feedback → file issues |
| `.claude/routines/tf-react.md`  | `issues` / `issue_comment` | Process owner approvals |
| `.claude/routines/tf-autofix.md`| `issues` labeled / PR sync | Start, iterate, merge one fix |
| `.claude/routines/tf-ship.md`   | PR merged + `auto-fix-ready` | Write WhatToTest → push main |
| `.claude/routines/tf-sweep.md`  | Schedule 1 hr | Catch dropped webhook events |

## If you invoked `/tf-cycle` intending to run one tick

Pick the specific phase you want and run that routine's prompt
directly in a session. Most of the time you want `tf-sweep` —
it re-dispatches any stuck state across all phases at once.

## Old local deployment (archived)

The launchd + smee + fastlane nightly path that this file used to
document no longer runs. `fastlane/Fastfile` and `fastlane/nightly.sh`
remain in the repo as a manual emergency-ship escape hatch, but
they're not wired to any automation.
