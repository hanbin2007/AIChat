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

# Run watch unit tests
xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" test

# Run watch UI tests
xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" -only-testing:"AIChat Watch AppUITests" test
```

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
