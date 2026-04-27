#!/bin/sh
set -eu

# Xcode Cloud post-build hook. Pulls UI-test screenshot attachments out of
# the .xcresult bundle and drops them under ci_artifacts/, which Xcode
# Cloud then publishes as downloadable artifacts on the build report (and
# on the PR check page when the build came from a PR).
#
# The watch and iOS UI tests already attach screenshots via
# XCTAttachment, but those live deep inside the .xcresult bundle and
# aren't browsable without downloading and opening the bundle locally.
# Surfacing them as plain PNGs makes UI-affecting builds reviewable
# directly from GitHub's check page.

if [ -z "${CI_PRIMARY_REPOSITORY_PATH:-}" ]; then
  echo "ci_post_xcodebuild: no repo on this runner; nothing to do"
  exit 0
fi

cd "$CI_PRIMARY_REPOSITORY_PATH"

# Only test workflows produce an .xcresult — archive/build runs have
# nothing to extract from.
case "${CI_XCODEBUILD_ACTION:-}" in
  test|test-without-building) ;;
  *)
    echo "ci_post_xcodebuild: action=${CI_XCODEBUILD_ACTION:-unknown}; no UI screenshots to extract"
    exit 0
    ;;
esac

if [ -z "${CI_RESULT_BUNDLE_PATH:-}" ] || [ ! -d "$CI_RESULT_BUNDLE_PATH" ]; then
  echo "ci_post_xcodebuild: no result bundle at CI_RESULT_BUNDLE_PATH; nothing to extract"
  exit 0
fi

OUT_DIR="$CI_PRIMARY_REPOSITORY_PATH/ci_artifacts/ui-screenshots"
mkdir -p "$OUT_DIR"

echo "ci_post_xcodebuild: extracting attachments from $CI_RESULT_BUNDLE_PATH into $OUT_DIR"

# Xcode 16+ exposes `xcresulttool export attachments`; older Xcode versions
# only support the legacy JSON dump. Try the new path first and fall back.
if xcrun xcresulttool export attachments \
     --path "$CI_RESULT_BUNDLE_PATH" \
     --output-path "$OUT_DIR" >/dev/null 2>&1; then
  echo "ci_post_xcodebuild: exported via 'xcresulttool export attachments'"
elif xcrun xcresulttool export object \
       --path "$CI_RESULT_BUNDLE_PATH" \
       --type directory \
       --output-path "$OUT_DIR" >/dev/null 2>&1; then
  echo "ci_post_xcodebuild: exported via legacy 'xcresulttool export object'"
else
  echo "ci_post_xcodebuild: xcresulttool export failed; copying full result bundle"
  cp -R "$CI_RESULT_BUNDLE_PATH" "$OUT_DIR/result.xcresult"
fi

# Discard non-image attachments (debug hierarchies, telemetry, plists)
# so the artifact archive stays a focused screenshot review surface.
find "$OUT_DIR" -type f \
  ! \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.heic' \) \
  -delete 2>/dev/null || true

# Prune now-empty intermediate directories left by `find -delete`.
find "$OUT_DIR" -type d -empty -delete 2>/dev/null || true

if [ ! -d "$OUT_DIR" ]; then
  echo "ci_post_xcodebuild: no image attachments found"
  exit 0
fi

count=$(find "$OUT_DIR" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.heic' \) | wc -l | tr -d ' ')
echo "ci_post_xcodebuild: kept $count screenshot file(s) under $OUT_DIR"

if [ "$count" = "0" ]; then
  rmdir "$OUT_DIR" 2>/dev/null || true
fi
