# Routines — cloud-hosted tf-cycle

This directory replaces the old local-Mac `/tf-cycle` loop. Each file
is the prompt for one Claude Code Routine hosted on Anthropic
infrastructure. There is no always-on daemon; every run is triggered
by a GitHub webhook or a schedule.

See `docs/xcode-cloud.md` for the Xcode Cloud side (build + TestFlight
upload). This file covers the Routines side.

## Routines to create

| File | Trigger | Purpose |
|---|---|---|
| `tf-triage.md` | Schedule: every 30 min | Pull new TF feedback → file issues |
| `tf-react.md` | GitHub `issues` / `issue_comment` with label `source:testflight-api` | Process owner approvals / refinements |
| `tf-autofix.md` | GitHub `issues` (labeled `auto-fix-approved`) **AND** `pull_request` sync on `autofix/*` | Start, iterate, merge one fix |
| `tf-ship.md` | GitHub `pull_request` closed + merged with label `auto-fix-ready` | Write WhatToTest → push main → wait for upload |
| `tf-sweep.md` | Schedule: every 1 hour | Fallback for dropped webhooks |

`_shared.md` is not a routine — it's included in every routine's
deployed prompt (paste at the top in the web UI, or `@include` it if
supported).

## One-time setup

1. **Install the Claude GitHub App** on `hanbin2007/AIChat` from
   claude.com settings.
2. **Create the 5 routines** at claude.ai/code/routines. For each:
   - Paste `_shared.md` content at the top of the prompt.
   - Append the routine file's content below.
   - Set the trigger per the table above.
   - Attach MCP connectors:
     - GitHub (built-in)
     - `testflight-feedback` (custom MCP — your existing server)
3. **Configure env vars** on each routine (Settings → Environment):
   - `ASC_KEY_ID` — App Store Connect API key ID
   - `ASC_ISSUER_ID` — ASC issuer ID
   - `ASC_PRIVATE_KEY` — ES256 private key (the `.p8` contents
     pasted as a single multi-line string). Mark as secret.
   - `ASC_PRODUCT_ID` — Xcode Cloud product id (from
     `GET /v1/ciProducts`)
   - `ASC_SHIP_WORKFLOW_ID` — workflow id for `Ship to TestFlight`
     (from `GET /v1/ciProducts/{id}/workflows`)
4. **Create the state issue** (first `tf-triage` run will do this
   automatically, but you can do it manually first):
   ```
   gh label create meta-state --color c5def5 --description "Routine state carrier"
   gh issue create --title "[meta] tf-cycle state — do not close" \
                   --label meta-state \
                   --body '{"tf_feedback_cursor":0,"last_triage_iso":"1970-01-01T00:00:00Z","last_ship_iso":"1970-01-01T00:00:00Z"}'
   gh issue pin <N>
   ```

## ASC JWT helper (for autofix log fetching and ship polling)

Both `tf-autofix` (iterate mode) and `tf-ship` (polling) need to call
the App Store Connect API. Use this bash snippet inside the routine
(requires `jq` and `openssl`):

```bash
asc_jwt() {
  local now=$(date +%s)
  local exp=$((now + 900))
  local header='{"alg":"ES256","kid":"'"$ASC_KEY_ID"'","typ":"JWT"}'
  local payload='{"iss":"'"$ASC_ISSUER_ID"'","iat":'"$now"',"exp":'"$exp"',"aud":"appstoreconnect-v1"}'
  local b64h=$(printf '%s' "$header"  | openssl base64 -A | tr '+/' '-_' | tr -d '=')
  local b64p=$(printf '%s' "$payload" | openssl base64 -A | tr '+/' '-_' | tr -d '=')
  local msg="$b64h.$b64p"
  local key_file=$(mktemp); printf '%s' "$ASC_PRIVATE_KEY" > "$key_file"
  local sig=$(printf '%s' "$msg" | openssl dgst -sha256 -sign "$key_file" \
              | openssl asn1parse -inform DER \
              | awk '/INTEGER/ {gsub("0x","",$NF); printf "%s", $NF}' \
              | xxd -r -p | openssl base64 -A | tr '+/' '-_' | tr -d '=')
  rm -f "$key_file"
  printf '%s.%s' "$msg" "$sig"
}

asc_get() {
  curl -sSf -H "Authorization: Bearer $(asc_jwt)" \
       "https://api.appstoreconnect.apple.com$1"
}
```

Use:
```bash
asc_get "/v1/ciProducts/$ASC_PRODUCT_ID/buildRuns?filter[workflow]=$ASC_SHIP_WORKFLOW_ID&sort=-createdDate&limit=1" \
  | jq -r '.data[0].attributes.executionProgress'
```

## Event coverage caveat

As of this writing, Claude Code Routines reliably supports
`pull_request`, `issues`, `issue_comment`, and `release` events with
label filters. If your Routines tier doesn't fire on `issues` with
label filters, `tf-sweep` at hourly cadence is the safety net — it
re-checks state and forcibly re-dispatches by toggling labels.

Do **not** rely on `workflow_run` or `check_run` events (Xcode Cloud
posts status via the GitHub app, which shows up as a PR sync — that
is what `tf-autofix` continuation listens to).

## Migration from the old local orchestrator

The old `.claude/commands/tf-cycle.md` is deprecated. Once these
routines are live and have processed at least one full issue
end-to-end (TF feedback → autofix → ship), you can:

1. `launchctl bootout gui/$(id -u)/com.user.aichat.gh-webhook` on
   the Mac (if it's still around)
2. Delete the smee channel
3. Remove the Mac's launchd nightly ship (`fastlane/nightly.sh`)
4. Keep `fastlane/Fastfile` + `fastlane/.env` locally as a manual
   emergency-ship escape hatch; they're not wired to anything
   automated anymore.

The `meta-state` issue replaces `tf-state.json`. The smee log
(`/tmp/aichat-gh-events.log`) is no longer consulted by any routine
— webhooks go directly from GitHub to the Claude GitHub App.
