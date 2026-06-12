#!/bin/sh
set -eu

# Runs after dependency resolution, before xcodebuild.
#
# TestFlight publishing is manual-only via fastlane. If an old Xcode Cloud
# archive workflow still exists in App Store Connect, fail before upload so
# the retired cloud release path cannot accidentally ship a build.
#
# For non-archive workflows, keep the old build-number alignment harmlessly
# available for PR/build diagnostics.

# Apple's test-without-building action runs on a fresh runner that never
# had a clone, so CI_PRIMARY_REPOSITORY_PATH is unset there. Without this
# guard `set -eu` aborts the whole pipeline (the .xctestproducts already
# carries the version baked in during build-for-testing — nothing to do
# on the test runner).
if [ -z "${CI_PRIMARY_REPOSITORY_PATH:-}" ]; then
  echo "ci_pre_xcodebuild: no repo on this runner (test-without-building); nothing to do"
  exit 0
fi

cd "$CI_PRIMARY_REPOSITORY_PATH"

if [ "${CI_XCODEBUILD_ACTION:-}" = "archive" ]; then
  echo "ci_pre_xcodebuild: Xcode Cloud archive/upload is retired. Use docs/manual-fastlane-release.md."
  exit 1
fi

if [ -z "${CI_BUILD_NUMBER:-}" ]; then
  echo "ci_pre_xcodebuild: CI_BUILD_NUMBER unset, skipping build-number bump"
  exit 0
fi

# Marketing version stays under human control via Config/Shared.xcconfig.
# Build (project) version is what TestFlight uses for uniqueness.
xcrun agvtool new-version -all "$CI_BUILD_NUMBER" >/dev/null
echo "ci_pre_xcodebuild: set CFBundleVersion to $CI_BUILD_NUMBER"
