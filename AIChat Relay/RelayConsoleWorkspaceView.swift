//
//  RelayConsoleWorkspaceView.swift
//  AIChat Relay
//
//  Created by Codex on 2026/3/15.
//

import SwiftUI

struct RelayConsoleWorkspaceView: View {
    @ObservedObject var controller: RelayServerController
    @ObservedObject private var settings: RelaySettingsStore

    @State private var activityFilter = ""
    @State private var debugFilter = ""
    @State private var severityFilter: RelayConsoleSeverityFilter = .all
    @State private var sourceFilter: RelayDebugSourceFilter = .all
    @State private var selectedDebugEntryID: RelayDebugEntry.ID?

    init(controller: RelayServerController) {
        self.controller = controller
        self._settings = ObservedObject(wrappedValue: controller.settings)
    }

    var body: some View {
        HSplitView {
            activityPane
                .frame(minWidth: 360, idealWidth: 420, maxWidth: 480)

            debugPane
                .frame(minWidth: 700, maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var activityPane: some View {
        RelayConsolePane {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Activity Stream")
                            .font(.system(size: 22, weight: .bold, design: .rounded))

                        Text("Operational events stay pinned in this pane. New records only affect the internal scroll area.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Clear") {
                        controller.clearLogEntries()
                    }
                    .buttonStyle(.bordered)
                    .disabled(controller.logEntries.isEmpty)
                }

                HStack(spacing: 10) {
                    RelayConsoleSearchField(text: $activityFilter, placeholder: "Search activity")

                    Picker("Severity", selection: $severityFilter) {
                        ForEach(RelayConsoleSeverityFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }

                HStack(spacing: 10) {
                    Label("\(filteredActivityEntries.count) visible", systemImage: "list.bullet.rectangle")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Copy Visible") {
                        controller.copyToPasteboard(filteredActivityLogText, label: "visible activity log")
                    }
                    .buttonStyle(.bordered)
                    .disabled(filteredActivityEntries.isEmpty)
                }

                if filteredActivityEntries.isEmpty {
                    RelayConsoleEmptyState(
                        symbol: controller.logEntries.isEmpty ? "text.badge.xmark" : "line.3.horizontal.decrease.circle",
                        title: controller.logEntries.isEmpty ? "No activity yet" : "No activity matches the filter",
                        message: controller.logEntries.isEmpty
                            ? "Start the relay and send requests to populate the activity stream."
                            : "Adjust the search text or severity filter to broaden the result set."
                    )
                } else {
                    List(filteredActivityEntries) { entry in
                        RelayConsoleActivityRow(entry: entry)
                            .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
    }

    private var debugPane: some View {
        RelayConsolePane {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Debug Inspector")
                            .font(.system(size: 22, weight: .bold, design: .rounded))

                        Text("Debug records are listed as structured events. Select a row to inspect the full payload on the right.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("Capture Debug", isOn: $settings.debugLoggingEnabled)
                        .toggleStyle(.switch)
                        .fixedSize()
                }

                HStack(spacing: 10) {
                    RelayConsoleSearchField(text: $debugFilter, placeholder: "Search source, path, address, body")

                    Picker("Source", selection: $sourceFilter) {
                        ForEach(RelayDebugSourceFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }

                HSplitView {
                    debugListPane
                        .frame(minWidth: 460, idealWidth: 560, maxWidth: 760)

                    debugDetailPane
                        .frame(minWidth: 280, maxWidth: .infinity)
                }
            }
        }
    }

    private var debugListPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("\(filteredDebugEntries.count) visible", systemImage: "ladybug")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Copy Visible") {
                    controller.copyToPasteboard(filteredDebugLogText, label: "visible debug log")
                }
                .buttonStyle(.bordered)
                .disabled(filteredDebugEntries.isEmpty)

                Button("Clear") {
                    controller.clearDebugEntries()
                    selectedDebugEntryID = nil
                }
                .buttonStyle(.bordered)
                .disabled(controller.debugEntries.isEmpty)
            }

            if settings.debugLoggingEnabled == false {
                RelayConsoleEmptyState(
                    symbol: "ladybug.slash",
                    title: "Debug capture is disabled",
                    message: "Enable debug capture to record client requests, relay responses, and Gemini upstream traffic.",
                    actionTitle: "Enable Debug Capture"
                ) {
                    settings.debugLoggingEnabled = true
                }
            } else if filteredDebugEntries.isEmpty {
                RelayConsoleEmptyState(
                    symbol: controller.debugEntries.isEmpty ? "ladybug" : "line.3.horizontal.decrease.circle",
                    title: controller.debugEntries.isEmpty ? "No debug records yet" : "No records match the filter",
                    message: controller.debugEntries.isEmpty
                        ? "Send a request through the relay to start collecting structured debug events."
                        : "Adjust the search text or source filter to broaden the result set."
                )
            } else {
                Table(filteredDebugEntries, selection: $selectedDebugEntryID) {
                    TableColumn("Status") { entry in
                        Text(entry.statusCode.map(String.init) ?? "—")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(debugStatusTint(for: entry.statusCode))
                    }
                    .width(min: 56, ideal: 64, max: 72)

                    TableColumn("Time") { entry in
                        Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .width(min: 100, ideal: 118, max: 128)

                    TableColumn("Source") { entry in
                        Text(entry.source.displayName)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .width(min: 70, ideal: 78, max: 88)

                    TableColumn("Kind") { entry in
                        Text(entry.kind.displayName)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .width(min: 76, ideal: 88, max: 96)

                    TableColumn("Method") { entry in
                        Text(entry.method ?? "—")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .width(min: 60, ideal: 70, max: 80)

                    TableColumn("Path") { entry in
                        Text(entry.path ?? "—")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                    }
                    .width(min: 180, ideal: 240, max: 360)

                    TableColumn("Address") { entry in
                        Text(entry.address ?? "—")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                    }
                    .width(min: 150, ideal: 180, max: 260)

                    TableColumn("Summary") { entry in
                        Text(entry.summary)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .lineLimit(1)
                    }
                    .width(min: 180, ideal: 220, max: 320)
                }
            }
        }
    }

    private var debugDetailPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Selected Record")
                    .font(.system(size: 16, weight: .bold, design: .rounded))

                Spacer()

                if let selectedDebugEntry {
                    Button("Copy Body") {
                        controller.copyToPasteboard(selectedDebugEntry.body, label: "debug record")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let selectedDebugEntry, filteredDebugEntries.contains(where: { $0.id == selectedDebugEntry.id }) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedDebugEntry.title)
                            .font(.system(size: 18, weight: .bold, design: .rounded))

                        Text(selectedDebugEntry.summary)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                        RelayDebugMetadataTile(label: "Time", value: selectedDebugEntry.timestamp.formatted(date: .abbreviated, time: .standard))
                        RelayDebugMetadataTile(label: "Source", value: selectedDebugEntry.source.displayName)
                        RelayDebugMetadataTile(label: "Kind", value: selectedDebugEntry.kind.displayName)
                        RelayDebugMetadataTile(label: "Status", value: selectedDebugEntry.statusCode.map(String.init) ?? "—")
                        RelayDebugMetadataTile(label: "Method", value: selectedDebugEntry.method ?? "—")
                        RelayDebugMetadataTile(label: "Path", value: selectedDebugEntry.path ?? "—")
                        RelayDebugMetadataTile(label: "Address", value: selectedDebugEntry.address ?? "—")
                    }

                    TextEditor(text: .constant(selectedDebugEntry.body))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.black.opacity(0.84))
                        )
                        .foregroundStyle(Color(red: 0.72, green: 0.95, blue: 0.79))
                }
            } else {
                RelayConsoleEmptyState(
                    symbol: "sidebar.right",
                    title: "Select a debug record",
                    message: "Choose a row from the debug list to inspect the full request or response payload."
                )
            }
        }
    }

    private var selectedDebugEntry: RelayDebugEntry? {
        guard let selectedDebugEntryID else {
            return nil
        }

        return controller.debugEntries.first(where: { $0.id == selectedDebugEntryID })
    }

    private var filteredActivityEntries: [RelayLogEntry] {
        controller.logEntries
            .reversed()
            .filter { entry in
                switch severityFilter {
                case .all:
                    break
                case .warningsAndErrors:
                    guard entry.level == .warning || entry.level == .error else {
                        return false
                    }
                case .errorsOnly:
                    guard entry.level == .error else {
                        return false
                    }
                }

                let normalizedFilter = activityFilter.trimmingCharacters(in: .whitespacesAndNewlines)
                guard normalizedFilter.isEmpty == false else {
                    return true
                }

                let haystack = [
                    entry.level.rawValue,
                    entry.message,
                    entry.timestamp.formatted(date: .abbreviated, time: .standard)
                ]
                .joined(separator: " ")
                .localizedLowercase

                return haystack.contains(normalizedFilter.localizedLowercase)
            }
    }

    private var filteredDebugEntries: [RelayDebugEntry] {
        controller.debugEntries
            .reversed()
            .filter { entry in
                switch sourceFilter {
                case .all:
                    break
                case .client:
                    guard entry.source == .client else {
                        return false
                    }
                case .relay:
                    guard entry.source == .relay else {
                        return false
                    }
                case .gemini:
                    guard entry.source == .upstream else {
                        return false
                    }
                }

                let normalizedFilter = debugFilter.trimmingCharacters(in: .whitespacesAndNewlines)
                guard normalizedFilter.isEmpty == false else {
                    return true
                }

                let haystack = [
                    entry.title,
                    entry.summary,
                    entry.source.displayName,
                    entry.kind.displayName,
                    entry.method ?? "",
                    entry.path ?? "",
                    entry.address ?? "",
                    entry.statusCode.map(String.init) ?? "",
                    entry.body
                ]
                .joined(separator: " ")
                .localizedLowercase

                return haystack.contains(normalizedFilter.localizedLowercase)
            }
    }

    private var filteredActivityLogText: String {
        filteredActivityEntries
            .map { entry in
                "[\(entry.timestamp.formatted(date: .omitted, time: .standard))] \(entry.level.rawValue.uppercased()) \(entry.message)"
            }
            .joined(separator: "\n")
    }

    private var filteredDebugLogText: String {
        filteredDebugEntries
            .map { entry in
                let metadata = [
                    "time=\(entry.timestamp.formatted(date: .abbreviated, time: .standard))",
                    "source=\(entry.source.displayName)",
                    "kind=\(entry.kind.displayName)",
                    "status=\(entry.statusCode.map(String.init) ?? "—")",
                    "method=\(entry.method ?? "—")",
                    "path=\(entry.path ?? "—")",
                    "address=\(entry.address ?? "—")"
                ]
                .joined(separator: " | ")

                return """
                \(entry.title) | \(metadata)
                \(entry.body)
                """
            }
            .joined(separator: "\n\n")
    }

    private func debugStatusTint(for statusCode: Int?) -> Color {
        guard let statusCode else {
            return .secondary
        }

        switch statusCode {
        case 200..<300:
            return Color.green
        case 300..<500:
            return Color.orange
        default:
            return Color.red
        }
    }
}

private enum RelayConsoleSeverityFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case warningsAndErrors = "Warn+Err"
    case errorsOnly = "Errors"

    var id: String { rawValue }
}

private enum RelayDebugSourceFilter: String, CaseIterable, Identifiable {
    case all = "All Sources"
    case client = "Client"
    case relay = "Relay"
    case gemini = "Gemini"

    var id: String { rawValue }
}

private struct RelayConsolePane<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
    }
}

private struct RelayConsoleSearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .rounded))

            if text.isEmpty == false {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}

private struct RelayConsoleEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        symbol: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)

            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))

            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if let actionTitle, let action {
                Button(actionTitle) {
                    action()
                }
                .buttonStyle(.bordered)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

private struct RelayConsoleActivityRow: View {
    let entry: RelayLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(levelTint)
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(entry.level.rawValue.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(levelTint)

                    Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text(entry.message)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var levelTint: Color {
        switch entry.level {
        case .info:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

private struct RelayDebugMetadataTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}
