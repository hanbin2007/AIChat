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
2. The watch is relay-only; populate `AI_RELAY_BASE_URL` and (optionally) `AI_RELAY_BEARER_TOKEN` in the xcconfig
3. In xcconfig, URLs must use `http:/$()/...` — `//` is treated as a comment

## Architecture

**Per-VM MVVM. No central store.**

- Each screen owns a `@MainActor final class` + `@Observable` ViewModel under `AIChat Watch App/Stores/` (e.g. `ConversationDetailViewModel`, `ConversationListViewModel`, `ActivationCenterViewModel`, `RelayPurchaseSheetViewModel`, `BillingViewModel`, `GlobalSettingsViewModel`, `FavoritesViewModel`, `PromptLibraryViewModel`, `RelayPairingTokenViewModel`).
- `AppEnvironment` (`AIChat Watch App/AppEnvironment.swift`) is the composition root. It owns the `RelayAPIClient` actor and the domain services (`ChatService`, `MemoryService`, `TranscriptionService`, `ConversationPersistence`, `BillingPersistence`, `SettingsService`, `RelayConnectionMonitor`) and is injected into the SwiftUI tree via `.environment(\.appEnvironment, ...)`. It does NOT hold ViewModels or shared UI state.
- Views construct their own VMs from injected services on navigation; there is no central `ChatStore` — that pattern is gone.
- The `ConversationPersistence` actor (`AIChat Watch App/Persistence/`) is the single source of truth for conversation data; subscribers receive change notifications via `stream() -> AsyncStream<[ConversationThread]>`.
- Bearer-key persistence is via `RelayKeyStore` (in `AppConfiguration.swift`) backed by an app-group `UserDefaults` suite; activation flows must write to it for the key to survive cold launches.

### Targets

| Target | Platform | Purpose |
|---|---|---|
| AIChat Watch App | watchOS | Primary app — standalone (`WKRunsIndependentlyOfCompanionApp`) |
| AIChat iOS App | iOS | Thin companion for offline activation key registration only |
| AIChat Relay | macOS | Native SwiftUI relay server with UI, logs, LAN address display |
| AIChat Watch Widget | watchOS | Complication/widget for quick new-conversation launch |
| Shared Licensing | cross-platform | Activation, deep links, localization (`L10n`), relay billing contracts |

### Watch App Layers

- **Models/** — `ConversationThread`, `ChatMessage`, `ChatAttachment`, `PromptPreset`, `AIModelCatalog`, `ConversationHistoryRenderBudget`, `AssistantMessageContentNormalizer` — plain `Codable` types and pure-function helpers
- **Services/** — `ChatService` (relay SSE streaming actor), `RelayAPIClient`, `RelayActivationService`, `RelayBillingService`, `MemoryService`, `TranscriptionService`, `VoiceRecorder`, `SettingsService`, `RelayConnectionMonitor`, `WatchDisplayStateMonitor`
- **Persistence/** — `AIChatSchemaV2.swift` (SwiftData entities), `ConversationPersistence` actor, `BillingPersistence`, `AIChatModelContainer`. V2 is the initial install schema; no V1 migration exists
- **Stores/** — per-screen ViewModels listed above
- **Views/** — SwiftUI views (currently a placeholder shell; the full UI surface is in active redesign)

### AI Backend

The watch is relay-only. `AppConfiguration.load()` resolves the relay base URL and bearer token at launch; `AppConfiguration.resolvedRelayBearerToken` reads from `RelayKeyStore` first and falls back to the xcconfig token. `ChatService` opens an SSE stream via `RelayAPIClient.streamChat(_:conversationID:)` and yields fresh `ConversationThread` snapshots through an `AsyncThrowingStream` for VM consumption.

### Local Swift Packages

- `Packages/MarkdownView` — custom Markdown renderer for watchOS
- `Packages/swiftui-math` — LaTeX/math formula rendering

### Persistence

- SwiftData V2 schema (11 entities, see `AIChatSchemaV2.swift`) backed by `AIChatModelContainer.makeOnDisk(...)`
- All conversation reads/writes go through the `ConversationPersistence` actor; subscribers observe changes via `stream() -> AsyncStream<[ConversationThread]>`
- Billing snapshot caching via `BillingPersistence`
- Bearer key via `RelayKeyStore` (UserDefaults, app-group when configured)

### Localization

Chinese (zh-Hans) and English via `L10n.swift` in `Shared Licensing/`. Use `L10n.tr("key")` for localized strings.

### UI Test Infrastructure

UI tests are intended to use environment variable `AIChat_UI_TEST_SCENARIO` to bootstrap specific `AppEnvironment` configurations with seeded data and mock streaming services. Test scenarios will be defined in `AIChatApp.swift` under `UITestBootstrap` (Phase 5 of the restoration roadmap; see `docs/watch-rewrite-restore-plan.md`).

**When you make UI-affecting changes, the change MUST be exercised by a test in `AIChat Watch AppUITests` or `AIChat iOS AppUITests` that calls `attachScreenshot(app, named:)` at the relevant moment.** Round-trip:

1. Xcode Cloud runs the dedicated `AIChat Watch UITests` / `AIChat iOS UITests` schemes.
2. `ci_scripts/ci_post_xcodebuild.sh` pulls every `XCTAttachment` screenshot from the `.xcresult` into `ci_artifacts/ui-screenshots/` (Xcode Cloud uploads `ci_artifacts/` as build artifacts).
3. `.github/workflows/ui-screenshots-bridge.yml` catches the Xcode Cloud `check_run.completed` and dispatches `ui-screenshots.yml`.
4. `ui-screenshots.yml` calls `python3 .claude/routines/scripts/asc.py artifacts --run "$RUN_ID"` to fetch the bundle via the ASC API, uploads PNGs as a workflow artifact, and posts (or updates) a single PR comment marked `<!-- ui-screenshots-bot:run=<id> -->`.

No screenshot attachment in the test ⇒ no visual review surface for the UI change.

## Relay server access (`ai.origenclub.cn`)

The production relay (`aichat-relay.service`, Next.js on `127.0.0.1:8787` behind Caddy 2.11.2) lives on an EC2 box (`ip-172-31-34-238`, public IP `13.212.1.7`, Ubuntu 24.04). The sandbox can SSH to it through a chisel WebSocket tunnel terminated at `wss://ai.origenclub.cn/_chisel/`.

Bring-up in a fresh sandbox session — requires two secrets in env (`CHISEL_SECRET`, `SSH_PRIVATE_KEY_B64`):

```bash
bash scripts/sandbox-tunnel.sh
ssh rt 'whoami; hostname'   # → ubuntu@ip-172-31-34-238
```

`scripts/sandbox-tunnel.sh` installs the chisel client + openssh-client if missing, drops the private key into `~/.ssh/id_relay`, writes a `Host rt` stanza to `~/.ssh/config`, and runs `chisel client` in the background (log: `~/.cache/sandbox-tunnel/chisel.log`, pid: `~/.cache/sandbox-tunnel/chisel.pid`). Subsequent invocations kill any prior client and reconnect.

Server-side bring-up (one-time, on the EC2 box) is `scripts/server-setup-chisel.sh` — installs chisel 1.10.1 as a `DynamicUser=yes` systemd unit (`/etc/systemd/system/chisel.service`) listening on `127.0.0.1:8080`, drops `users.json` via `LoadCredential=`, and patches `/etc/caddy/Caddyfile` to add `handle_path /_chisel/* { reverse_proxy 127.0.0.1:8080 }` ahead of the existing catch-all `reverse_proxy 127.0.0.1:8787`. See `docs/relay-server-setup.md` for the full topology, verification, and revoke/rotate steps.
