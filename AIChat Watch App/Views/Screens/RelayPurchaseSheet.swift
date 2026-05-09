//
//  RelayPurchaseSheet.swift
//  AIChat Watch App
//
//  Modal credit purchase surface. The actual StoreKit 2
//  `Product.purchase(options:)` call lives in the (still-pending)
//  `BillingPurchaseCoordinator`. This sheet:
//    • loads the catalog
//    • on tap, asks the relay for an `appAccountToken`
//    • surfaces the prepared state so the future coordinator can pick
//      up and run `Product.purchase`
//
//  Until the coordinator ships, the "Buy" button toggles into a
//  "Prepared — pending StoreKit" state and surfaces the token. This
//  keeps the UX honest about what's wired vs. pending.
//

import SwiftUI

struct RelayPurchaseSheet: View {
    @Environment(\.appEnvironment) private var environment

    let onDismiss: () -> Void

    @State private var viewModel: RelayPurchaseSheetViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    content(vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Buy Credits")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
        .task {
            guard let env = environment, let service = env.billingService else { return }
            if viewModel == nil {
                let vm = RelayPurchaseSheetViewModel(billing: service)
                viewModel = vm
                await vm.loadCatalog()
            }
        }
    }

    @ViewBuilder
    private func content(_ vm: RelayPurchaseSheetViewModel) -> some View {
        Form {
            balanceSection(vm)
            plansSection(vm)
            statusSection(vm)
        }
    }

    @ViewBuilder
    private func balanceSection(_ vm: RelayPurchaseSheetViewModel) -> some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Text("Balance")
                Spacer()
                Text("\(vm.balance ?? 0)")
                    .font(.title3.monospacedDigit())
            }
        }
    }

    @ViewBuilder
    private func plansSection(_ vm: RelayPurchaseSheetViewModel) -> some View {
        Section("Plans") {
            if vm.plans.isEmpty {
                if vm.loadState == .loading {
                    ProgressView()
                } else {
                    Text("No plans available.")
                        .font(DS.Typography.bubbleMeta)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(vm.plans) { plan in
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(plan.title)
                            .font(DS.Typography.listTitle)
                        HStack {
                            Text("\(plan.monthlyCredits) credits / mo")
                                .font(DS.Typography.listPreview)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Buy") {
                                Task { await vm.preparePurchase() }
                            }
                            .controlSize(.mini)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statusSection(_ vm: RelayPurchaseSheetViewModel) -> some View {
        switch vm.purchaseState {
        case .idle:
            EmptyView()
        case .preparing:
            Section {
                ProgressView("Preparing…")
            }
        case .readyToPurchase(let token):
            Section {
                Label("Prepared — pending StoreKit", systemImage: "clock")
                    .font(DS.Typography.bubbleMeta)
                    .foregroundStyle(.secondary)
                Text("Token: \(token.uuidString.prefix(8))…")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        case .submitting:
            Section { ProgressView("Submitting…") }
        case .completed:
            Section {
                Label("Completed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(DS.Status.ok)
            }
        case .failed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(DS.Status.danger)
                    .font(DS.Typography.bubbleMeta)
            }
        }
    }
}
