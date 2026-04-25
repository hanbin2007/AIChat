# Xcode Cloud Setup

This file documents what you (a human) configured in App Store Connect →
Xcode Cloud, so we have a snapshot to detect drift later. The actual
workflow definitions live in ASC's Web UI; only the in-repo pieces
(`ci_scripts/*`, `TestFlight/WhatToTest.*.txt`) are version-controlled.

## One-time bootstrap

1. **Grant Xcode Cloud access to the repo**
   - Install the [Xcode Cloud GitHub App](https://github.com/apps/xcode-cloud)
     on `hanbin2007/AIChat`.
2. **Create the product**
   - In Xcode (App Manager → Cloud) or ASC, create an Xcode Cloud product
     pointing at `AIChat.xcodeproj`, primary scheme `AIChat iOS App`.
3. **Set environment variables on every workflow** (Settings → Environment):
   - `AI_RELAY_BASE_URL` (required, **secret**) — production relay URL,
     `https://...`
   - `AI_RELAY_BEARER_TOKEN` (required, **secret**) — relay shared bearer
   - `AI_RELAY_ALLOW_INSECURE_TLS` (optional) — `YES` only when the relay
     uses a self-signed cert (don't ship to TF this way)
   - `APP_GROUP_IDENTIFIER` (optional) — only if app group is used

## Workflows to create

### A. `PR Build & Test`

| | |
|---|---|
| **Start condition** | Pull Request Changes → target branch `main` |
| **Environment** | Latest Release Xcode, latest macOS |
| **Actions** | 1. Test `AIChat Watch App` (any watchOS sim, any watch) <br> 2. Build `AIChat iOS App` (generic iOS device) <br> 3. Build `AIChat Relay` (generic macOS) |
| **Post-actions** | none |

The test action lets ASC pick a fresh sim each run — do **not** pin a UDID
here (the local `CLAUDE.md` UDID is for `zhb`'s machine only).

Pre-build script (`ci_post_clone.sh`) writes `Config/Secrets.xcconfig` from
the env vars above. Build-number script (`ci_pre_xcodebuild.sh`) is a
no-op for this workflow but harmless.

### B. `Ship to TestFlight`

| | |
|---|---|
| **Start condition** | Branch Changes → `main` (every push) |
| **Environment** | Latest Release Xcode, latest macOS |
| **Actions** | Archive `AIChat iOS App`, deployment preparation `TestFlight (External Testing)` |
| **Post-actions** | TestFlight External Testing → group `PBTestGroup` |

`ci_pre_xcodebuild.sh` aligns `CFBundleVersion` with `CI_BUILD_NUMBER` so
each ship gets a unique build number with no commit-back loop. Changelog
comes from `TestFlight/WhatToTest.<LOCALE>.txt` files in the repo —
the `tf-ship` routine (see `.claude/routines/tf-ship.md`) writes these
before pushing `main`.

## Manual emergency-ship escape hatch

`fastlane/Fastfile` stays in the repo as a manual-only escape hatch.
If Xcode Cloud is unavailable and you need to ship a build immediately,
run `fastlane beta changelog:"..."` from any Mac with Xcode + the ASC
key. There is no automated path that invokes it — the old launchd
`fastlane/nightly.sh` and its smee/webhook daemon are gone along with
the local orchestrator.
