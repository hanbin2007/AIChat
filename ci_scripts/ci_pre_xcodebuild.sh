#!/bin/sh
set -eu

# Runs after dependency resolution, before xcodebuild. We use it to align
# CFBundleVersion with Xcode Cloud's monotonic CI_BUILD_NUMBER so every
# uploaded TestFlight build has a unique number without committing back
# to the repo (which the old fastlane lane had to do).
#
# Only meaningful for archive workflows. PR/test workflows can run this
# too — agvtool just no-ops if the value is unchanged.

cd "$CI_PRIMARY_REPOSITORY_PATH"

if [ -z "${CI_BUILD_NUMBER:-}" ]; then
  echo "ci_pre_xcodebuild: CI_BUILD_NUMBER unset, skipping build-number bump"
  exit 0
fi

# Marketing version stays under human control via Config/Shared.xcconfig.
# Build (project) version is what TestFlight uses for uniqueness.
xcrun agvtool new-version -all "$CI_BUILD_NUMBER" >/dev/null
echo "ci_pre_xcodebuild: set CFBundleVersion to $CI_BUILD_NUMBER"
