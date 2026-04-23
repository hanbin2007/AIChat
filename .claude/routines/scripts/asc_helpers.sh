#!/usr/bin/env bash
# Source this from any routine bash block that wants to `curl` ASC directly.
#
# Usage:
#   source "$(git rev-parse --show-toplevel)/.claude/routines/scripts/asc_helpers.sh"
#   asc_get /v1/ciBuildRuns/<id>
#
# For anything more involved than one-shot GET, prefer `asc.py` —
# it handles pagination, included-resource resolution, and feedback
# normalization.

_asc_script_dir() {
  local src="${BASH_SOURCE[0]}"
  cd "$(dirname "$src")" && pwd
}

asc_jwt() {
  python3 "$(_asc_script_dir)/asc.py" jwt
}

asc_get() {
  curl -sSfL \
    -H "Authorization: Bearer $(asc_jwt)" \
    "https://api.appstoreconnect.apple.com$1"
}
