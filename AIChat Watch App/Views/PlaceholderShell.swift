//
//  PlaceholderShell.swift
//  AIChat Watch App
//
//  Minimal SwiftUI shell that lets the app launch and exercises the
//  rewritten ViewModel layer. UI/UX is intentionally placeholder —
//  the real visual design ships in a follow-up phase that consumes
//  the same ViewModels without refactoring them.
//

import SwiftUI

struct PlaceholderShell: View {
    @Environment(\.appEnvironment) private var environment

    var body: some View {
        if let env = environment {
            TabView {
                ConversationsTab(environment: env)
                    .tag(0)
                FavoritesTab(environment: env)
                    .tag(1)
                ActivationTab(environment: env)
                    .tag(2)
                BillingTab(environment: env)
                    .tag(3)
                SettingsTab(environment: env)
                    .tag(4)
            }
            .tabViewStyle(.page)
        } else {
            VStack(spacing: 8) {
                Text("AIChat")
                    .font(.headline)
                Text("Composition root unavailable.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ConversationsTab: View {
    let environment: AppEnvironment
    @State private var viewModel: ConversationListViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    List {
                        Button("New Conversation") {
                            Task { await vm.createNew() }
                        }
                        ForEach(vm.items, id: \.id) { thread in
                            VStack(alignment: .leading) {
                                Text(thread.title).font(.headline)
                                Text(thread.messages.last?.text ?? "")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task { await vm.delete(id: thread.id) }
                                } label: { Text("Delete") }
                            }
                        }
                    }
                } else {
                    ProgressView("Loading…")
                }
            }
            .navigationTitle("Chats")
        }
        .task {
            guard let persistence = environment.conversations else { return }
            let vm = ConversationListViewModel(persistence: persistence)
            vm.start()
            viewModel = vm
        }
    }
}

private struct FavoritesTab: View {
    let environment: AppEnvironment
    @State private var viewModel: FavoritesViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    if vm.items.isEmpty {
                        Text(vm.isLoaded ? "No favorites yet." : "Loading…")
                            .foregroundStyle(.secondary)
                    } else {
                        List(vm.items, id: \.id) { thread in
                            Text(thread.title)
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Favorites")
        }
        .task {
            guard let persistence = environment.conversations else { return }
            let vm = FavoritesViewModel(persistence: persistence)
            vm.start()
            viewModel = vm
        }
    }
}

private struct ActivationTab: View {
    let environment: AppEnvironment
    @State private var viewModel: ActivationCenterViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    VStack(spacing: 8) {
                        if let balance = vm.creditBalance {
                            Text("Credits: \(balance)")
                        }
                        if let key = vm.currentBearerKey {
                            Text("Key: \(key.prefix(12))…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Button("Bootstrap") { Task { await vm.bootstrap() } }
                        Button("Refresh Status") { Task { await vm.refreshStatus() } }
                    }
                } else {
                    Text("Activation unavailable")
                }
            }
            .navigationTitle("Activation")
        }
        .task {
            guard let service = environment.activationService else { return }
            viewModel = ActivationCenterViewModel(service: service)
        }
    }
}

private struct BillingTab: View {
    let environment: AppEnvironment
    @State private var viewModel: BillingViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    VStack(spacing: 8) {
                        if let balance = vm.balance {
                            Text("Balance: \(balance)")
                        }
                        if vm.lowBalance { Text("Low balance").foregroundStyle(.orange) }
                        Button("Refresh") { Task { await vm.refresh() } }
                        ForEach(vm.plans, id: \.id) { plan in
                            VStack(alignment: .leading) {
                                Text(plan.title).font(.headline)
                                Text("\(plan.monthlyCredits) credits / mo")
                                    .font(.footnote)
                            }
                        }
                    }
                    .padding()
                } else {
                    Text("Billing unavailable")
                }
            }
            .navigationTitle("Billing")
        }
        .task {
            guard let service = environment.billingService else { return }
            viewModel = BillingViewModel(service: service)
        }
    }
}

private struct SettingsTab: View {
    let environment: AppEnvironment

    var body: some View {
        NavigationStack {
            Form {
                Section("Relay") {
                    Text(environment.connectionMonitor.description)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
