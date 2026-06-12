# Xcode Cloud Setup (Retired For Releases)

TestFlight publishing has moved to local manual fastlane. See
`docs/manual-fastlane-release.md`.

This file remains only as historical context for the old Xcode Cloud
setup. Do not recreate the `Ship to TestFlight` workflow unless you are
intentionally restoring cloud publishing.

Repository backstop: `ci_scripts/ci_pre_xcodebuild.sh` now fails Xcode
Cloud `archive` actions, so a forgotten ASC workflow cannot silently
publish a build.

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

### B. `Ship to TestFlight` (retired)

| | |
|---|---|
| **Start condition** | Branch Changes → `main` (every push) |
| **Environment** | Latest Release Xcode, latest macOS |
| **Actions** | Archive `AIChat iOS App`, deployment preparation `TestFlight (External Testing)` |
| **Post-actions** | TestFlight External Testing → group `PBTestGroup` |

This workflow is retired. Local fastlane now owns build-number creation,
archive, upload, and TestFlight distribution.
