---
description: DEPRECATED — see .claude/routines/ for the cloud-hosted version
---

The always-on local orchestrator is gone. The TestFlight feedback →
GitHub review → autofix loop now runs as Claude Code Routines hosted
on Anthropic infrastructure plus small GitHub Actions workflows for
events Routines doesn't expose. TestFlight publishing itself is
manual-only via fastlane.

See `.claude/routines/README.md` for the full architecture and
deployment steps. The pieces are:

| File | Runner | Trigger | Purpose |
|---|---|---|---|
| `.claude/routines/tf-triage.md` | Routine | Schedule 30 min | Pull TF feedback → file issues |
| `.claude/routines/tf-react.md`  | Routine | `issues` / `issue_comment` | Process owner approvals |
| `.claude/routines/tf-autofix.md`| GitHub Actions | `issues.labeled` / `check_run.completed` | Start, iterate, merge one fix |

## If you invoked `/tf-cycle` intending to run one tick

Pick the specific phase you want and run that routine's prompt
directly in a session. If something looks stuck, manually re-fire
`tf-autofix.yml` from the Actions UI on the issue you want.

## Local deployment

The launchd + smee + fastlane nightly path that this file used to
document no longer runs. `fastlane/Fastfile` is now the only
TestFlight publishing path; see `docs/manual-fastlane-release.md`.
