# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Working principles

**Tests serve the user, not the other way around.** Passing tests is never the goal — improving real user experience is. When tests fail, fix the underlying user-facing problem (or fix the test if it's wrong about the contract). Never weaken behavior, hide UI, strip animations, or contort production code purely to make a red test go green. If the only way you can make a test pass is by degrading what a real user sees or feels, stop and reconsider — the test is probably miscalibrated, or the production code has a real issue that the test is half-detecting. Fix the right thing.

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
