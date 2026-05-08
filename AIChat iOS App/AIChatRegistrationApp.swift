//
//  AIChatRegistrationApp.swift
//  AIChat (iOS)
//
//  Two build modes:
//
//  - **Default** (no `COMPANION_APP` flag): ships as the offline
//    activation keygen tool — renders `OfflineActivationKeygenView`
//    only. This is the iOS app's documented purpose per
//    `CLAUDE.md`.
//
//  - **`COMPANION_APP` flag set**: was the full-featured iPhone
//    companion driving `ChatStore`. The Watch rewrite removed
//    `ChatStore` and the legacy services, so the companion is in a
//    placeholder state until it gets its own MVVM rewrite that
//    consumes the new `ConversationPersistence` /
//    `RelayBillingService` / `RelayActivationService` directly. The
//    follow-up roadmap is tracked in
//    `docs/watch-rewrite-missing-features.md` § 3.2.
//

import SwiftUI

@main
struct AIChatRegistrationApp: App {
    var body: some Scene {
        WindowGroup {
            #if COMPANION_APP
            CompanionPlaceholderView()
            #else
            OfflineActivationKeygenView()
            #endif
        }
    }
}

#if COMPANION_APP
private struct CompanionPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "applewatch.and.arrow.forward")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("AIChat Companion")
                .font(.headline)
            Text("The iPhone companion is being rewritten on the new Watch architecture. Please use the Watch app directly for now.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }
}
#endif
