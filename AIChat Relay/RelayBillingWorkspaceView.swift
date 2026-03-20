import SwiftUI

struct RelayBillingWorkspaceView: View {
    @ObservedObject var controller: RelayServerController

    @State private var accountFilter = ""
    @State private var selectedAccountID: UUID?
    @State private var selectedDeviceID: String?
    @State private var selectedKeyID: UUID?
    @State private var selectedGrantID: UUID?

    @State private var accountDisplayName = ""
    @State private var accountAdminNote = ""
    @State private var accountState = RelayAccountState.active
    @State private var accountPlanID = ""
    @State private var grantCredits = "1000"
    @State private var grantNote = ""
    @State private var grantExpiresAt = Date.now.addingTimeInterval(30 * 24 * 60 * 60)
    @State private var grantHasExpiry = true

    @State private var deviceAlias = ""
    @State private var deviceNote = ""

    @State private var keyState = RelayKeyState.active
    @State private var keyNote = ""

    @State private var grantRemainingCredits = ""
    @State private var storedGrantNote = ""

    @State private var policyJSON = ""
    @State private var plansJSON = ""

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        accountsPanel
                        devicesPanel
                    }

                    VStack(spacing: 18) {
                        accountsPanel
                        devicesPanel
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        keysPanel
                        grantsPanel
                    }

                    VStack(spacing: 18) {
                        keysPanel
                        grantsPanel
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        usagePanel
                        policyPanel
                    }

                    VStack(spacing: 18) {
                        usagePanel
                        policyPanel
                    }
                }
            }
            .padding(.top, 8)
        }
        .onAppear {
            syncPolicyEditors()
            hydrateAccountEditor()
            hydrateDeviceEditor()
            hydrateKeyEditor()
            hydrateGrantEditor()
        }
        .onChange(of: controller.billingPolicy) { _, _ in
            syncPolicyEditors()
        }
        .onChange(of: controller.billingPlans) { _, _ in
            syncPolicyEditors()
        }
        .onChange(of: selectedAccountID) { _, _ in
            hydrateAccountEditor()
        }
        .onChange(of: selectedDeviceID) { _, _ in
            hydrateDeviceEditor()
        }
        .onChange(of: selectedKeyID) { _, _ in
            hydrateKeyEditor()
        }
        .onChange(of: selectedGrantID) { _, _ in
            hydrateGrantEditor()
        }
    }

    private var filteredAccounts: [RelayAccountSummary] {
        let normalizedFilter = accountFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedFilter.isEmpty == false else {
            return controller.billingAccounts
        }

        return controller.billingAccounts.filter { account in
            [
                account.displayName,
                account.adminNote,
                account.planID,
                account.originalTransactionID,
                account.accountID.uuidString
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
            .contains(normalizedFilter)
        }
    }

    private var selectedAccount: RelayAccountSummary? {
        controller.billingAccounts.first(where: { $0.accountID == selectedAccountID })
    }

    private var selectedDevice: RelayDeviceSummary? {
        controller.billingDevices.first(where: { $0.deviceID == selectedDeviceID })
    }

    private var selectedKey: RelayKeySummary? {
        controller.billingKeys.first(where: { $0.keyID == selectedKeyID })
    }

    private var selectedGrant: RelayGrantSummary? {
        controller.billingGrants.first(where: { $0.grantID == selectedGrantID })
    }

    private var headerCard: some View {
        GroupBox {
            HStack(spacing: 18) {
                summaryMetric(title: "Accounts", value: "\(controller.billingAccountCount)")
                summaryMetric(title: "Active Keys", value: "\(controller.activeKeyCount)")
                summaryMetric(title: "Credits", value: "\(controller.totalManagedCredits)")
                summaryMetric(title: "Usage Rows", value: "\(controller.billingUsage.count)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Billing Workspace", systemImage: "creditcard.and.123")
        }
    }

    private var accountsPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Search accounts", text: $accountFilter)
                    .textFieldStyle(.roundedBorder)

                List(filteredAccounts, id: \.accountID, selection: $selectedAccountID) { account in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.displayName?.isEmpty == false ? account.displayName! : account.accountID.uuidString)
                            .font(.headline)
                        Text("\(account.state.rawValue) • \(account.creditBalance) credits")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 220)

                Divider()

                if let selectedAccount {
                    Text("Account Editor")
                        .font(.headline)

                    TextField("Display name", text: $accountDisplayName)
                    TextField("Admin note", text: $accountAdminNote, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)

                    Picker("State", selection: $accountState) {
                        ForEach(RelayAccountState.allCases, id: \.self) { state in
                            Text(state.rawValue).tag(state)
                        }
                    }

                    TextField("Plan ID", text: $accountPlanID)

                    HStack {
                        Button("Save Account") {
                            controller.updateAccount(
                                accountID: selectedAccount.accountID,
                                displayName: accountDisplayName,
                                adminNote: accountAdminNote,
                                state: accountState,
                                planID: accountPlanID
                            )
                        }
                        .buttonStyle(.borderedProminent)

                        Spacer()

                        Text(selectedAccount.accountID.uuidString)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    Text("Manual Credit Grant")
                        .font(.subheadline.weight(.semibold))

                    TextField("Credits", text: $grantCredits)
                    TextField("Grant note", text: $grantNote)
                    Toggle("Set expiry", isOn: $grantHasExpiry)
                    if grantHasExpiry {
                        DatePicker("Expires At", selection: $grantExpiresAt)
                    }

                    Button("Grant Credits") {
                        controller.grantCredits(
                            accountID: selectedAccount.accountID,
                            credits: Int(grantCredits) ?? 0,
                            expiresAt: grantHasExpiry ? grantExpiresAt : nil,
                            note: grantNote
                        )
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text("Select an account to edit profile, note, plan, or grant credits.")
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("Accounts", systemImage: "person.crop.square.stack")
        }
    }

    private var devicesPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                List(controller.billingDevices, id: \.deviceID, selection: $selectedDeviceID) { device in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.alias?.isEmpty == false ? device.alias! : device.deviceID)
                            .font(.headline)
                        Text("\(device.platform.rawValue) • \(device.lastSeenAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 220)

                Divider()

                if let selectedDevice {
                    Text("Device Editor")
                        .font(.headline)
                    TextField("Alias", text: $deviceAlias)
                    TextField("Note", text: $deviceNote, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                    Button("Save Device") {
                        controller.updateDevice(
                            deviceID: selectedDevice.deviceID,
                            alias: deviceAlias,
                            note: deviceNote
                        )
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("Select a device to edit alias and note.")
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("Devices", systemImage: "iphone.gen3")
        }
    }

    private var keysPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                List(controller.billingKeys, id: \.keyID, selection: $selectedKeyID) { key in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(key.keyValue)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                        Text("\(key.state.rawValue) • \(key.source.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 220)

                Divider()

                if let selectedKey {
                    Text("Key Editor")
                        .font(.headline)
                    Picker("State", selection: $keyState) {
                        ForEach(RelayKeyState.allCases, id: \.self) { state in
                            Text(state.rawValue).tag(state)
                        }
                    }
                    TextField("Note", text: $keyNote, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                    Button("Save Key") {
                        controller.updateKey(
                            keyID: selectedKey.keyID,
                            state: keyState,
                            note: keyNote
                        )
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("Select a key to pause, revoke, or annotate it.")
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("Keys", systemImage: "key")
        }
    }

    private var grantsPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                List(controller.billingGrants, id: \.grantID, selection: $selectedGrantID) { grant in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(grant.remainingCredits) / \(grant.totalCredits) credits")
                            .font(.headline)
                        Text("\(grant.source.rawValue) • \(grant.expiresAt?.formatted(date: .abbreviated, time: .shortened) ?? "No expiry")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 220)

                Divider()

                if let selectedGrant {
                    Text("Grant Editor")
                        .font(.headline)
                    TextField("Remaining credits", text: $grantRemainingCredits)
                    TextField("Note", text: $storedGrantNote, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                    Button("Save Grant") {
                        controller.updateGrant(
                            grantID: selectedGrant.grantID,
                            remainingCredits: Int(grantRemainingCredits),
                            note: storedGrantNote
                        )
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("Select a grant to edit its remaining credits or note.")
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("Grants", systemImage: "shippingbox")
        }
    }

    private var usagePanel: some View {
        GroupBox {
            List(controller.billingUsage, id: \.requestID) { usage in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(usage.endpoint) • \(usage.modelID)")
                        .font(.headline)
                    Text("in \(usage.inputTokens) • out \(usage.outputTokens) • credits \(usage.settledCredits)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(usage.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minHeight: 340)
        } label: {
            Label("Recent Usage", systemImage: "chart.xyaxis.line")
        }
    }

    private var policyPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Metering Policy JSON")
                    .font(.headline)
                TextEditor(text: $policyJSON)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 180)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))

                Text("Plan Catalog JSON")
                    .font(.headline)
                TextEditor(text: $plansJSON)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 140)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))

                HStack {
                    Button("Reload JSON") {
                        syncPolicyEditors()
                    }
                    .buttonStyle(.bordered)

                    Button("Save Policy") {
                        savePolicyFromEditors()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } label: {
            Label("Policy And Plans", systemImage: "slider.horizontal.3")
        }
    }

    @ViewBuilder
    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hydrateAccountEditor() {
        guard let selectedAccount else {
            accountDisplayName = ""
            accountAdminNote = ""
            accountPlanID = ""
            accountState = .active
            return
        }

        accountDisplayName = selectedAccount.displayName ?? ""
        accountAdminNote = selectedAccount.adminNote ?? ""
        accountPlanID = selectedAccount.planID ?? ""
        accountState = selectedAccount.state
    }

    private func hydrateDeviceEditor() {
        guard let selectedDevice else {
            deviceAlias = ""
            deviceNote = ""
            return
        }

        deviceAlias = selectedDevice.alias ?? ""
        deviceNote = selectedDevice.note ?? ""
    }

    private func hydrateKeyEditor() {
        guard let selectedKey else {
            keyState = .active
            keyNote = ""
            return
        }

        keyState = selectedKey.state
        keyNote = selectedKey.note ?? ""
    }

    private func hydrateGrantEditor() {
        guard let selectedGrant else {
            grantRemainingCredits = ""
            storedGrantNote = ""
            return
        }

        grantRemainingCredits = "\(selectedGrant.remainingCredits)"
        storedGrantNote = selectedGrant.note ?? ""
    }

    private func syncPolicyEditors() {
        policyJSON = prettyJSONString(for: controller.billingPolicy) ?? ""
        plansJSON = prettyJSONString(for: controller.billingPlans) ?? ""
    }

    private func savePolicyFromEditors() {
        guard let policyData = policyJSON.data(using: .utf8),
              let plansData = plansJSON.data(using: .utf8)
        else {
            controller.showFeedback(title: "Invalid JSON", message: "Policy editor contains unreadable text.", style: .error)
            return
        }

        do {
            let policy = try decoder.decode(RelayMeteringPolicySnapshot.self, from: policyData)
            let plans = try decoder.decode([RelayPlanCatalogItem].self, from: plansData)
            controller.saveBillingPolicy(policy, plans: plans)
        } catch {
            controller.showFeedback(title: "Policy Parse Failed", message: error.localizedDescription, style: .error)
        }
    }

    private func prettyJSONString<T: Encodable>(for value: T) -> String? {
        guard let data = try? encoder.encode(value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
