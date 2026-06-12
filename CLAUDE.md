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
xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,id=89095621-9CFA-4FD3-BB9E-1091E04D796E" test

# Run watch UI tests
xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,id=89095621-9CFA-4FD3-BB9E-1091E04D796E" -only-testing:"AIChat Watch AppUITests" test

# UI-test-only schemes (used by Xcode Cloud to surface screenshots)
xcodebuild -scheme "AIChat Watch UITests" -destination "platform=watchOS Simulator,id=89095621-9CFA-4FD3-BB9E-1091E04D796E" test
xcodebuild -scheme "AIChat iOS UITests"   -destination "platform=iOS Simulator,name=iPhone 17" test
```

**Known-good simulator (verified 2026-06-12):**
- Apple Watch Series 11 (46mm), watchOS 26.5, UDID `89095621-9CFA-4FD3-BB9E-1091E04D796E`, paired with iPhone 17 Pro Max UDID `2162AE93-D5B3-443C-B116-0258CF7B759B`. Other installed watchOS simulators may not be reliably usable (unpaired / name collisions / stale CoreSimulator state).
- Write tests as `async throws` even when the logic is synchronous — watchOS 26 has a test-runner launch race that segfaults the first sync `@MainActor` test per process.

**Important: Always verify changes compile before finishing. Run relevant tests when modifying testable code. Fix all build errors and test failures before considering work complete.**

## Local Configuration

1. Copy `Config/Secrets.xcconfig.example` → `Config/Secrets.xcconfig` (gitignored)
2. Configure `AI_RELAY_BASE_URL`; do not put upstream Gemini keys or relay admin bearer tokens in client config
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
- **Services/** — `RelayAIClient` (relay proxy), Gemini request-shaping helpers, `ConversationRepository` (JSON file persistence), `ICloudConversationSyncService`, `CompanionSyncBridge` (WatchConnectivity), `VoiceRecorder`, `AIContextBuilder`, `AIMemoryMaintenanceService`
- **ViewModels/** — `ChatStore` only
- **Views/** — SwiftUI views; `ContentView` is a root `TabView` (Favorites / PromptLibrary / Conversations)

### AI Backend

The Watch app is relay-only. `AIServiceFactory` always creates `RelayAIClient`,
and the relay server holds the upstream Gemini API key and forwards SSE streams
as `answer_delta` / `thought_delta` events. `AI_BACKEND_MODE` is no longer read
by `AppConfiguration.load()`.

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

The production relay (`aichat-relay.service`, standalone Next.js on
`127.0.0.1:8787` behind Caddy 2.11.2) runs on an EC2 box
(`ip-172-31-34-238`, public IP `13.212.1.7`, Ubuntu 24.04) in
`ap-southeast-1`.

Preferred access is direct SSH:

```bash
ssh ubuntu@13.212.1.7
```

If the instance does not already trust a local key, use EC2 Instance Connect to
push the current public key temporarily, then SSH with the matching private key:

```bash
aws ec2-instance-connect send-ssh-public-key \
  --region ap-southeast-1 \
  --instance-id i-053c0e9ac3927e1b5 \
  --availability-zone ap-southeast-1a \
  --instance-os-user ubuntu \
  --ssh-public-key "$(cat ~/.ssh/id_ed25519.pub)"

ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes ubuntu@13.212.1.7
```

Useful read-only version checks:

```bash
systemctl show aichat-relay.service -p WorkingDirectory -p ExecStart --no-pager
curl -fsS http://127.0.0.1:8787/api/health
cd /opt/aichat-relay && cat package.json && cat .next/BUILD_ID
```

Full server notes live in `docs/relay-server-setup.md`.

## Next.js relay testing

**All tests for the Next.js relay run in the sandbox. Never run tests on the EC2 box** — the production host is not a test runner. If the sandbox is missing a dependency (Node version, system package, browser binary for Playwright, etc.), install it in the sandbox; do not work around it by SSHing to EC2.

Required test layers for the Next.js relay project (all three must exist and pass):

- **Unit tests** (`tests/unit/**`) — pure functions, utility modules, and route handlers exercised in isolation.
- **Integration tests** (`tests/api/**`, `tests/ui/**`) — API routes exercised end-to-end against in-process Next.js handlers (including SSE streaming contracts `answer_delta` / `thought_delta` and billing/auth middleware), plus React component trees rendered under happy-dom.
- **E2E tests** (`tests/e2e/**/*.e2e.test.ts`) — HTTP flows against a real `next start` process. Boot is owned by `tests/e2e/global-setup.ts`; use `npm run test:e2e`.

```bash
cd relay
npm test              # unit + integration (vitest)
npm run test:coverage # unit + integration with coverage
npm run test:e2e      # E2E only (requires `npm run build` first)
npm run test:all      # both, in series
```

**Coverage floor: the whole Next.js project must report >70% line coverage.** Server-rendered `page.tsx` files under `src/app/` are excluded from the vitest scope because they only run inside the Next runtime; they are covered by the E2E suite which renders each admin page over HTTP. The threshold (`coverage.thresholds`) is enforced in `vitest.config.ts`, so `npm run test:coverage` fails if any of lines/statements/functions/branches falls below 70%.
