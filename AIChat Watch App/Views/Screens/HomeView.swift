//
//  HomeView.swift
//  AIChat Watch App
//
//  The first screen users see. Section-based layout (no TabView):
//    1. Primary action — "New Conversation"
//    2. Configuration banner (only when relay is misconfigured)
//    3. Low-balance banner (only when balance is low)
//    4. Recent conversations (5 most recent)
//    5. Quick links — Favorites / Prompts
//    6. Account & Settings
//
//  Toolbar:
//    • leading: RelayStatusDot mirroring `RelayConnectionMonitor`
//
//  Tapping a recent conversation pushes `Route.conversationDetail(id)`
//  via the bound navigation path.
//

import SwiftUI

struct HomeView: View {
    @Environment(\.appEnvironment) private var environment
    @Binding var path: NavigationPath

    @State private var listVM: ConversationListViewModel?
    @State private var billingVM: BillingViewModel?

    var body: some View {
        List {
            primaryActionSection
            statusBannersSection
            recentSection
            quickLinksSection
            accountSection
        }
        .listStyle(.carousel)
        .navigationTitle("AIChat")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if let env = environment {
                    RelayStatusDot(state: env.connectionMonitor.state)
                }
            }
        }
        .task {
            guard let env = environment else { return }
            if listVM == nil, let persistence = env.conversations {
                let vm = ConversationListViewModel(persistence: persistence)
                vm.start()
                listVM = vm
            }
            if billingVM == nil, let service = env.billingService {
                let vm = BillingViewModel(service: service)
                billingVM = vm
                await vm.refresh()
            }
        }
    }

    // MARK: - Sections

    private var primaryActionSection: some View {
        Section {
            Button {
                Task { await createConversation() }
            } label: {
                Label("New Conversation", systemImage: "plus.circle.fill")
                    .font(DS.Typography.listTitle)
            }
            .listItemTint(.accentColor)
        }
    }

    @ViewBuilder
    private var statusBannersSection: some View {
        if let banner = configurationBanner {
            Section {
                ConfigurationBannerView(
                    message: banner.message,
                    severity: banner.severity,
                    action: banner.action
                )
                .listRowBackground(Color.clear)
            }
        }
        if let billingVM, billingVM.lowBalance {
            Section {
                ConfigurationBannerView(
                    message: "Credit balance is low. Top up to keep sending.",
                    severity: .warning
                ) {
                    path.append(Route.accountCenter)
                }
                .listRowBackground(Color.clear)
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if let listVM, !listVM.items.isEmpty {
            Section("Recent") {
                ForEach(listVM.items.prefix(5)) { thread in
                    Button {
                        path.append(Route.conversationDetail(thread.id))
                    } label: {
                        conversationRow(thread)
                    }
                    .buttonStyle(.plain)
                }
                Button("All Conversations") {
                    path.append(Route.allConversations)
                }
                .font(DS.Typography.listPreview)
            }
        } else if listVM != nil {
            Section {
                EmptyStateView(
                    symbol: "bubble.left.and.bubble.right",
                    title: "No conversations yet",
                    subtitle: "Tap \"New Conversation\" to start chatting."
                )
                .listRowBackground(Color.clear)
            }
        }
    }

    private var quickLinksSection: some View {
        Section {
            Button {
                path.append(Route.favorites)
            } label: {
                Label("Favorites", systemImage: "star")
            }
            Button {
                path.append(Route.promptLibrary)
            } label: {
                Label("Prompt Library", systemImage: "text.book.closed")
            }
        }
    }

    private var accountSection: some View {
        Section {
            Button {
                path.append(Route.accountCenter)
            } label: {
                HStack {
                    Label("Account", systemImage: "person.crop.circle")
                    Spacer()
                    if let balance = billingVM?.balance {
                        Text("\(balance)")
                            .font(DS.Typography.bubbleMeta)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                path.append(Route.globalSettings)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }

    // MARK: - Row

    private func conversationRow(_ thread: ConversationThread) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                if thread.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                Text(thread.title)
                    .font(DS.Typography.listTitle)
                    .lineLimit(1)
            }
            Text(thread.previewText)
                .font(DS.Typography.listPreview)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Helpers

    private func createConversation() async {
        guard let listVM else { return }
        if let id = await listVM.createNew() {
            path.append(Route.conversationDetail(id))
        }
    }

    private struct Banner {
        let message: String
        let severity: ConfigurationBannerView.Severity
        let action: (() -> Void)?
    }

    private var configurationBanner: Banner? {
        guard let env = environment else { return nil }
        if env.relayAPI == nil {
            return Banner(
                message: "Relay isn't configured. Add AI_RELAY_BASE_URL to ship.",
                severity: .error,
                action: nil
            )
        }
        if case .offline(let reason) = env.connectionMonitor.state {
            return Banner(
                message: reason,
                severity: .warning,
                action: { path.append(Route.accountCenter) }
            )
        }
        return nil
    }
}
