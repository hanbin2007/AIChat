#!/bin/bash
# Nightly TestFlight build — invoked by launchd at 00:00 local time.
# Pulls latest main, builds, uploads to TestFlight external group.

set -euo pipefail

REPO="/Users/zhb/Documents/aichat"
LOG_DIR="$REPO/fastlane/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/nightly-$(date +%F).log"
# Prune logs older than 14 days, then cap this run's log at 100 MB. head closes
# the pipe at the cap and the resulting SIGPIPE kills the run, so a stuck or
# interactive prompt can never fill the disk again (see incident 2026-05-24:
# a wrong gym scheme dropped into an interactive picker and the loop wrote 58 GB).
find "$LOG_DIR" -name 'nightly-*.log' -mtime +14 -delete 2>/dev/null || true
exec > >(head -c 104857600 > "$LOG") 2>&1

echo "===== Nightly run $(date -Iseconds) ====="

cd "$REPO"

# Ensure clean state and latest main
git fetch origin main --quiet
git checkout main --quiet
git reset --hard origin/main --quiet

# Source ASC credentials + TF group
set -a
source fastlane/.env
set +a

# PATH for brew-installed fastlane (launchd has minimal PATH)
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# Changelog: list fixes closed in the last 24h + 5 most recent commits.
RECENT_FIXES=$(/opt/homebrew/bin/gh issue list \
  --repo hanbin2007/AIChat \
  --state closed \
  --label shipped-to-testflight \
  --search "closed:>=$(date -u -v-1d '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '1 day ago' '+%Y-%m-%dT%H:%M:%SZ')" \
  --json number,title \
  --jq '.[] | "  #\(.number) \(.title)"' 2>/dev/null || echo "  (no recent shipped fixes)")

RECENT_COMMITS=$(git log --oneline -5 | sed 's/^/  /')

CHANGELOG="Nightly build $(date '+%Y-%m-%d')

Fixes shipped in last 24h:
$RECENT_FIXES

Recent commits:
$RECENT_COMMITS"

# Wall-clock cap (1h) when a timeout binary is available, so a silent hang can't
# wedge the run indefinitely. Plain run if neither timeout nor gtimeout exists.
if TIMEOUT_BIN="$(command -v timeout || command -v gtimeout)"; then
  "$TIMEOUT_BIN" 3600 fastlane beta changelog:"$CHANGELOG"
else
  fastlane beta changelog:"$CHANGELOG"
fi
echo "===== Nightly done $(date -Iseconds) ====="
