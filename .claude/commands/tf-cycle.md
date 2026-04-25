---
description: DEPRECATED — see .claude/routines/ for the cloud-hosted version
---

The always-on local orchestrator is gone. The TestFlight feedback →
GitHub review → autofix → ship loop now runs as Claude Code Routines
hosted on Anthropic infrastructure plus a small GitHub Actions
workflow for events Routines doesn't expose. Every run is triggered
by a GitHub webhook or a schedule; there is no daemon.

See `.claude/routines/README.md` for the full architecture and
deployment steps. The pieces are:

| File | Runner | Trigger | Purpose |
|---|---|---|---|
| `.claude/routines/tf-triage.md` | Routine | Schedule 30 min | Pull TF feedback → file issues |
| `.claude/routines/tf-react.md`  | Routine | `issues` / `issue_comment` | Process owner approvals |
| `.claude/routines/tf-autofix.md`| GitHub Actions | `issues.labeled` / `check_run.completed` | Start, iterate, merge one fix |
| `.claude/routines/tf-ship.md`   | Routine | PR merged + `auto-fix-ready` | Write WhatToTest → push main |
| `.claude/routines/tf-ship-finalize.md` | GitHub Actions | `check_run.completed` on `main` matching `Ship to TestFlight` | Close issues after Xcode Cloud uploads |

## If you invoked `/tf-cycle` intending to run one tick

Pick the specific phase you want and run that routine's prompt
directly in a session. If something looks stuck, manually re-fire
`tf-autofix.yml` from the Actions UI on the issue you want.

## Old local deployment (archived)

The launchd + smee + fastlane nightly path that this file used to
document no longer runs. `fastlane/Fastfile` and `fastlane/nightly.sh`
remain in the repo as a manual emergency-ship escape hatch, but
they're not wired to any automation.
