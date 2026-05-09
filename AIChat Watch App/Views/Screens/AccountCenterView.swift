//
//  AccountCenterView.swift
//  AIChat Watch App
//
//  Combined activation + billing surface. Shows current account state,
//  credit balance, plan list, and three primary actions:
//    • Bootstrap (first launch / re-bootstrap if relay accepts it)
//    • Show pairing token (sheet)
//    • Enter offline activation code (push)
//
//  Surface design favors a single scrollable Form with three sections —
//  matches watchOS Settings idioms and avoids horizontal swipes.
//

import SwiftUI

struct AccountCenterView: View {
    @Environment(\.appEnvironment) private var environment
    @Binding var path: NavigationPath

    @State private var activation: ActivationCenterViewModel?
    @State private var billing: BillingViewModel?
    @State private var presentingPairing: Bool = false
    @State private var presentingPurchase: Bool = false

    var body: some View {
        Group {
            if let activation, let billing {
                content(activation: activation, billing: billing)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Account")
        .task {
            guard let env = environment else { return }
            if activation == nil, let service = env.activationService {
                activation = ActivationCenterViewModel(
                    service: service,
                    appGroupIdentifier: env.configuration.appGroupIdentifier
                )
                await activation?.refreshStatus()
            }
            if billing == nil, let service = env.billingService {
                let vm = BillingViewModel(service: service)
                billing = vm
                await vm.refresh()
            }
        }
        .sheet(isPresented: $presentingPairing) {
            RelayPairingTokenSheet(onDismiss: { presentingPairing = false })
        }
        .sheet(isPresented: $presentingPurchase) {
            RelayPurchaseSheet(onDismiss: { presentingPurchase = false })
        }
    }

    @ViewBuilder
    private func content(activation: ActivationCenterViewModel, billing: BillingViewModel) -> some View {
        Form {
            Section {
                ActivationStatusCard(
                    status: activation.status,
                    lowBalanceThreshold: billing.snapshot?.catalog?.meteringPolicy.lowBalanceThresholdCredits
                )
                .listRowBackground(Color.clear)
            }

            Section("Actions") {
                Button {
                    Task { await activation.bootstrap() }
                } label: {
                    Label("Bootstrap", systemImage: "arrow.up.circle")
                }
                .disabled(activation.bootstrapState == .running)
                Button {
                    Task { await activation.refreshStatus() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button {
                    presentingPairing = true
                } label: {
                    Label("Pair Device", systemImage: "qrcode")
                }
                Button {
                    path.append(Route.offlineActivation)
                } label: {
                    Label("Offline Activation", systemImage: "key")
                }
            }

            if !billing.plans.isEmpty {
                Section("Plans") {
                    ForEach(billing.plans) { plan in
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text(plan.title)
                                .font(DS.Typography.listTitle)
                            Text("\(plan.monthlyCredits) credits / mo")
                                .font(DS.Typography.listPreview)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        presentingPurchase = true
                    } label: {
                        Label("Buy Credits", systemImage: "cart")
                    }
                }
            }

            if case .failed(let message) = activation.bootstrapState {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(DS.Status.danger)
                        .font(DS.Typography.bubbleMeta)
                }
            }
        }
    }
}
