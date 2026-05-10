# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Watch app
xcodebuild -scheme "AIChat Watch App" -destination "generic/platform=watchOS" build

# Watch app (simulator, for testing)
xcodebuild -scheme "AIChat Watch App" -destination "generic/platform=watchOS Simulator" build-for-testing

# macOS Relay app
xcodebuild -project AIChat.xcodeproj -scheme "AIChat Relay" -destination "platform=macOS" build

# Run watch unit tests (use the paired simulator by ID — `name=` is ambiguous
# on machines with multiple Apple Watch Series 11 46mm runtimes installed)
xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,id=93A83695-2859-4388-B337-957616D03F55" test

# Run watch UI tests
xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,id=93A83695-2859-4388-B337-957616D03F55" -only-testing:"AIChat Watch AppUITests" test

# UI-test-only schemes (used by Xcode Cloud to surface screenshots)
xcodebuild -scheme "AIChat Watch UITests" -destination "platform=watchOS Simulator,id=93A83695-2859-4388-B337-957616D03F55" test
xcodebuild -scheme "AIChat iOS UITests"   -destination "platform=iOS Simulator,name=iPhone 17" test
```

**Known-good simulator (verified 2026-04-19):**
- Apple Watch Series 11 (46mm), watchOS 26.0, UDID `93A83695-2859-4388-B337-957616D03F55`, paired with iPhone 17 UDID `471F8F79-1922-43C8-A613-168B1E4C15CA`. Other installed watchOS simulators are not reliably usable (unpaired / name collisions across 26.0 and 26.2 runtimes).
- Write tests as `async throws` even when the logic is synchronous — watchOS 26 has a test-runner launch race that segfaults the first sync `@MainActor` test per process.

**Important: Always verify changes compile before finishing. Run relevant tests when modifying testable code. Fix all build errors and test failures before considering work complete.**

## Local Configuration

1. Copy `Config/Secrets.xcconfig.example` → `Config/Secrets.xcconfig` (gitignored)
2. Set `AI_BACKEND_MODE` to `direct` (dev) or `relay` (production)
3. In xcconfig, URLs must use `http:/$()/...` — `//` is treated as a comment

## Architecture

**MVVM with a single central ObservableObject store.**

- `ChatStore` (`AIChat Watch App/ViewModels/ChatStore.swift`) is the sole `@StateObject` source of truth, injected via `.environmentObject()` from the `@main` app entry point
- Views read from and send actions to `ChatStore`; they never talk to services directly

### Targets

| Target | Platform | Purpose |
|---|---|---|
| AIChat Watch App | watchOS | Primary app — standalone (`WKRunsIndependentlyOfCompanionApp`) |
| AIChat iOS App | iOS | Thin companion for offline activation key registration only |
| AIChat Relay | macOS | Native SwiftUI relay server with UI, logs, LAN address display |
| AIChat Watch Widget | watchOS | Complication/widget for quick new-conversation launch |
| Shared Licensing | cross-platform | Activation, deep links, localization (`L10n`), relay billing contracts |

### Watch App Layers

- **Models/** — `ConversationThread`, `ChatMessage`, `ChatAttachment`, `PromptPreset`, `AIModelCatalog` — plain `Codable` structs
- **Services/** — `GeminiAPIClient` (direct), `RelayAIClient` (relay proxy), `ConversationRepository` (JSON file persistence), `ICloudConversationSyncService`, `CompanionSyncBridge` (WatchConnectivity), `VoiceRecorder`, `AIContextBuilder`, `AIMemoryMaintenanceService`
- **ViewModels/** — `ChatStore` only
- **Views/** — SwiftUI views; `ContentView` is a root `TabView` (Favorites / PromptLibrary / Conversations)

### AI Backend Modes

Controlled by `AI_BACKEND_MODE` in xcconfig, read at launch via `AppConfiguration.load()`:

- **direct** — watch calls Gemini API directly (dev only)
- **relay** — watch calls a relay server that holds the API key and forwards SSE streams as `answer_delta` / `thought_delta` events

`AIServiceFactory` creates the appropriate `AIStreamingService` implementation based on the mode.

### Local Swift Packages

- `Packages/MarkdownView` — custom Markdown renderer for watchOS
- `Packages/swiftui-math` — LaTeX/math formula rendering

### Persistence

- Conversations are stored as individual JSON files via `ConversationRepository`
- iCloud sync via `ICloudConversationSyncService` using CloudKit document storage
- Activation state via `ActivationRepository`

### Localization

Chinese (zh-Hans) and English via `L10n.swift` in `Shared Licensing/`. Use `L10n.tr("key")` for localized strings.

### UI Test Infrastructure

UI tests use environment variable `AIChat_UI_TEST_SCENARIO` to bootstrap specific `ChatStore` configurations with seeded data and mock streaming services. Test scenarios are defined in `AIChatApp.swift` under `UITestBootstrap`.

**When you make UI-affecting changes, the change MUST be exercised by a test in `AIChat Watch AppUITests` or `AIChat iOS AppUITests` that calls `attachScreenshot(app, named:)` at the relevant moment.** Round-trip:

1. Xcode Cloud runs the dedicated `AIChat Watch UITests` / `AIChat iOS UITests` schemes.
2. `ci_scripts/ci_post_xcodebuild.sh` pulls every `XCTAttachment` screenshot from the `.xcresult` into `ci_artifacts/ui-screenshots/` (Xcode Cloud uploads `ci_artifacts/` as build artifacts).
3. `.github/workflows/ui-screenshots-bridge.yml` catches the Xcode Cloud `check_run.completed` and dispatches `ui-screenshots.yml`.
4. `ui-screenshots.yml` calls `python3 .claude/routines/scripts/asc.py artifacts --run "$RUN_ID"` to fetch the bundle via the ASC API, uploads PNGs as a workflow artifact, and posts (or updates) a single PR comment marked `<!-- ui-screenshots-bot:run=<id> -->`.

No screenshot attachment in the test ⇒ no visual review surface for the UI change.

## Relay server access (`ai.origenclub.cn`)

The production relay (`aichat-relay.service`, Next.js on `127.0.0.1:8787` behind Caddy 2.11.2) runs on an EC2 box (`ip-172-31-34-238`, public IP `13.212.1.7`, Ubuntu 24.04). The sandbox has HTTPS-only egress, so SSH to the box rides over a chisel WebSocket tunnel terminated by Caddy at `wss://ai.origenclub.cn/_chisel/`.

```
sandbox  ──HTTPS──▶  Caddy :443 (ai.origenclub.cn)
                       ├─ /_chisel/*  ──▶  chisel server :8080 (loopback, DynamicUser systemd)
                       │                       └── tunnels TCP ──▶  127.0.0.1:22 (sshd)
                       └─ everything else ──▶  Next.js :8787 (aichat-relay)
```

### Sandbox-side bring-up

Two env secrets must be set in the Claude Code on the web "Secrets" UI (the sandbox does not hot-reload them — a new session is required for newly-added secrets to be visible):

| name                  | value                                                                  |
|-----------------------|------------------------------------------------------------------------|
| `CHISEL_SECRET`       | 64-hex emitted at the end of `scripts/server-setup-chisel.sh`          |
| `SSH_PRIVATE_KEY_B64` | `base64 -w0 < <key>` for a private key whose pubkey is in `~ubuntu/.ssh/authorized_keys` |

Bring up the tunnel in any fresh session:

```bash
bash scripts/sandbox-tunnel.sh
ssh rt 'whoami; hostname'   # → ubuntu@ip-172-31-34-238
```

`scripts/sandbox-tunnel.sh` is idempotent. It:

1. Downloads chisel 1.10.1 to `~/.local/bin/chisel` if missing.
2. `apt-get install`s `openssh-client` if `ssh` isn't on PATH.
3. Decodes `SSH_PRIVATE_KEY_B64` into `~/.ssh/id_relay` (chmod 600).
4. Writes (or replaces) a `Host rt` stanza in `~/.ssh/config` pointing at `127.0.0.1:2222` with `IdentitiesOnly=yes`, `StrictHostKeyChecking=accept-new`, `UserKnownHostsFile=~/.ssh/known_hosts_relay`, `ServerAliveInterval=30`.
5. Kills any prior chisel client (pid file: `~/.cache/sandbox-tunnel/chisel.pid`) and starts a new one in the background, logging to `~/.cache/sandbox-tunnel/chisel.log`. Connection target: `https://ai.origenclub.cn/_chisel/`, forward `2222:127.0.0.1:22`.
6. Smoke-tests `ssh rt 'whoami; hostname'`.

If the tunnel drops mid-session (`ssh rt` hangs / "Connection refused"), re-run `bash scripts/sandbox-tunnel.sh` — it'll reconnect.

### Server-side bring-up (one-time, on the EC2 box)

Run as `ubuntu`:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hanbin2007/AIChat/<branch>/scripts/server-setup-chisel.sh)
```

What it does:

- Installs chisel 1.10.1 to `/usr/local/bin/chisel`.
- Writes `/etc/chisel/users.json` with a freshly generated `sandbox:<SECRET>` entry, allowed dial target locked to `127.0.0.1:22`. Re-running rotates the SECRET.
- Writes `/etc/systemd/system/chisel.service` — `DynamicUser=yes`, `ProtectSystem=strict`, `ProtectHome=yes`, `NoNewPrivileges=yes`. The auth file is delivered via `LoadCredential=users.json:/etc/chisel/users.json`, exposed to chisel as `${CREDENTIALS_DIRECTORY}/users.json` (DynamicUser can't read root-owned 0640 files directly).
- Backs up `/etc/caddy/Caddyfile` to `/etc/caddy/Caddyfile.bak.pre-chisel` and (if the `/_chisel/` route isn't already present) rewrites it to insert `handle_path /_chisel/* { reverse_proxy 127.0.0.1:8080 }` ahead of `handle { reverse_proxy 127.0.0.1:8787 ... }`. The catch-all is wrapped in `handle {}` so Caddy's directive ordering routes `/_chisel/*` first. Caddy handles WebSocket Upgrade transparently; no header dance needed.
- Validates and reloads Caddy (`sudo caddy validate ... && sudo systemctl reload caddy`).
- Verifies with `curl http://127.0.0.1:8080/` and `curl https://ai.origenclub.cn/_chisel/` — both should return `Not found` (chisel's default response on a non-WebSocket GET; content-length 9). Identical bodies → routing is live.
- Prints the new `CHISEL_SECRET` for paste-back into the sandbox env.

### Rotation / revocation

Rotate the chisel secret (chisel keeps running, tunnel briefly drops):

```bash
# on EC2:
SECRET=$(openssl rand -hex 32)
sudo tee /etc/chisel/users.json >/dev/null <<JSON
{ "sandbox:${SECRET}": ["127.0.0.1:22"] }
JSON
sudo chmod 0640 /etc/chisel/users.json
sudo systemctl restart chisel
echo "new CHISEL_SECRET=${SECRET}"   # → update sandbox env
```

Rotate the SSH key: regenerate locally (`ssh-keygen -t ed25519 -f /tmp/k`), replace the `sandbox@aichat-relay` line in `~ubuntu/.ssh/authorized_keys`, update `SSH_PRIVATE_KEY_B64` in the sandbox env.

Revoke entirely:

```bash
sudo systemctl disable --now chisel
sudo cp /etc/caddy/Caddyfile.bak.pre-chisel /etc/caddy/Caddyfile
sudo systemctl reload caddy
sudo rm -f /etc/systemd/system/chisel.service /etc/chisel/users.json
sudo systemctl daemon-reload
```

### Troubleshooting

| symptom | likely cause | fix |
|---|---|---|
| `curl /_chisel/` → 502 from Caddy | chisel.service not running | `sudo journalctl -u chisel -n 50`; usually a permission issue with `users.json` if you bypassed `LoadCredential=` |
| `curl /_chisel/` → 404 with `via: 1.1 Caddy`, body `Not found`, content-length 9 | **healthy** — chisel's default response to non-WebSocket GET | none, this is success |
| `curl /_chisel/` → Next.js 404 (HTML or different body) | Caddyfile missing `handle_path /_chisel/*`, or didn't reload | `sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile && sudo systemctl reload caddy` |
| `ssh rt` → `Permission denied (publickey)` | pubkey not in `~ubuntu/.ssh/authorized_keys`, or key/secret pair mismatched (one was rotated, the other wasn't) | re-run server `server-setup-chisel.sh` AND replace authorized_keys; refresh both sandbox secrets |
| `ssh rt` → connection refused on `127.0.0.1:2222` | chisel client crashed in sandbox | `cat ~/.cache/sandbox-tunnel/chisel.log`; rerun `bash scripts/sandbox-tunnel.sh` |
| Sandbox env shows secrets blank | secrets added after this session started | start a new Claude Code on the web session; secrets only inject at sandbox boot |

Full topology + manual fallback in `docs/relay-server-setup.md`.
