//
//  OfflineActivationView.swift
//  AIChat Watch App
//
//  Manual offline-code redemption. Shows the watch's request fingerprint
//  (so the user can paste it into the iPhone keygen) and a multi-line
//  text field for entering the activation code. On submit, decodes the
//  license locally for grant metadata, then reports it to the relay.
//

import SwiftUI

struct OfflineActivationView: View {
    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: ActivationCenterViewModel?
    @State private var requestCode: String = ""
    @State private var activationCode: String = ""
    @State private var fingerprint: String = ""
    @State private var feedback: Feedback?

    private struct Feedback {
        let message: String
        let kind: Kind
        enum Kind { case ok, error }
    }

    var body: some View {
        Form {
            requestSection
            inputSection
            actionsSection
            if let feedback {
                Section {
                    Label(feedback.message,
                          systemImage: feedback.kind == .ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(feedback.kind == .ok ? DS.Status.ok : DS.Status.danger)
                        .font(DS.Typography.bubbleMeta)
                }
            }
        }
        .navigationTitle("Offline")
        .task {
            guard let env = environment, let service = env.activationService else { return }
            if viewModel == nil {
                viewModel = ActivationCenterViewModel(service: service)
            }
            // Build a request code locally so the user can hand it to
            // the iPhone keygen tool.
            let deviceToken = OfflineActivation.deviceToken(for: env.deviceIdentity.rawIdentifier)
            requestCode = OfflineActivation.makeRequestCode(deviceToken: deviceToken)
            fingerprint = OfflineActivation.displayToken(for: deviceToken)
        }
    }

    private var requestSection: some View {
        Section("Device Request") {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(OfflineActivation.formatForDisplay(requestCode))
                    .font(.system(.caption2, design: .monospaced))
                Text("Device ID: \(fingerprint)")
                    .font(DS.Typography.bubbleMeta)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var inputSection: some View {
        Section("Activation Code") {
            TextField("Enter code", text: $activationCode, axis: .vertical)
                .lineLimit(2...5)
                .textInputAutocapitalization(.characters)
        }
    }

    private var actionsSection: some View {
        Section {
            Button("Apply Code") {
                Task { await applyCode() }
            }
            .disabled(activationCode.trimmingCharacters(in: .whitespaces).isEmpty
                      || viewModel?.offlineRedeemState == .running)
            Button(role: .destructive) {
                activationCode = ""
                feedback = nil
            } label: {
                Text("Clear")
            }
        }
    }

    private func applyCode() async {
        guard let env = environment, let viewModel else { return }
        let trimmed = activationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let license = try OfflineActivation.decodeActivationCode(trimmed)
            let allowedModels = LicensedModelCatalog.modelIDs(for: license.modelMask)?.sorted()
            await viewModel.redeemOffline(
                code: trimmed,
                creditsTotal: license.messageLimit,
                creditsRemaining: license.messageLimit,
                validUntil: license.validUntil,
                allowedModelIDs: allowedModels,
                fingerprint: fingerprint
            )
            switch viewModel.offlineRedeemState {
            case .success:
                feedback = Feedback(message: "Activation applied.", kind: .ok)
            case .failed(let message):
                feedback = Feedback(message: message, kind: .error)
            default:
                feedback = nil
            }
            // Touch env so the compiler treats the capture as
            // intentional even if logging is added later.
            _ = env
        } catch {
            feedback = Feedback(message: error.localizedDescription, kind: .error)
        }
    }
}
