# Manual Fastlane Release

This is the only supported TestFlight publishing path. Xcode Cloud may
still be used for PR checks or UI screenshot artifacts, but it must not
archive or upload release builds.

Disable the old App Store Connect Xcode Cloud `Ship to TestFlight`
workflow in the ASC web UI. As a repository-level backstop,
`ci_scripts/ci_pre_xcodebuild.sh` fails any Xcode Cloud `archive` action
with a pointer back to this runbook.

## Prerequisites

Run from a Mac with Xcode, command-line tools, Ruby/Bundler, and an App
Store Connect API key.

Required local files and environment:

- `fastlane/.env` with:
  - `ASC_KEY_ID`
  - `ASC_ISSUER_ID`
  - `ASC_KEY_PATH`
  - `TESTFLIGHT_EXTERNAL_GROUP` (defaults to `PBTestGroup` if omitted)
- `ASC_KEY_PATH` must point to an existing `.p8` private key file.
- Locale must be UTF-8:

```bash
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
```

Install Ruby dependencies:

```bash
bundle install
```

If Bundler itself is missing, install the version from `Gemfile.lock`:

```bash
gem install bundler:4.0.8
```

## Preflight

Preflight checks credentials, locale, the ASC key file, and git
cleanliness without uploading anything:

```bash
cd /Users/zhb/Documents/AIChat
set -a; source fastlane/.env; set +a
bundle exec fastlane ios preflight
```

By default the release lane refuses to run with a dirty working tree.
For an emergency archive from a known dirty tree:

```bash
bundle exec fastlane ios preflight allow_dirty:true
```

## Release

Use an explicit changelog:

```bash
bundle exec fastlane ios beta changelog:"Fixes activation state refresh and relay entitlement handling."
```

Or use the default changelog file:

```bash
bundle exec fastlane ios beta
```

The default changelog file is `TestFlight/WhatToTest.en.txt`. To use a
different file:

```bash
bundle exec fastlane ios beta changelog_file:"TestFlight/WhatToTest.zh-Hans.txt"
```

The lane generates a UTC timestamp build number by default, for example
`202606120215`. To force a value:

```bash
bundle exec fastlane ios beta build_number:202606120215 changelog:"..."
```

## Behavior

The lane:

1. Validates credentials, key file, UTF-8 locale, and git cleanliness.
2. Temporarily writes `CFBundleVersion` into the iOS container app, watch
   app, and watch widget Info.plists.
3. Archives scheme `AIChat` with Release configuration.
4. Uploads to TestFlight and distributes to the configured external group.
5. Restores the original local `CFBundleVersion` values.

It does **not** commit, push, or trigger Xcode Cloud.

After a successful release, close shipped TestFlight feedback issues by
adding `shipped-to-testflight` and closing the issue.
