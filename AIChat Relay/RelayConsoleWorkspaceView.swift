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

    @State private var filter: RelayConsoleFilterState = .default
    @State private var isShowingFilterSheet = false
    @State private var isShowingTimeMenu = false
    @State private var selectedDebugEntryID: RelayDebugEntry.ID?

    init(controller: RelayServerController) {
        self.controller = controller
        self._settings = ObservedObject(wrappedValue: controller.settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            filterBar

            if filter.isActive {
                RelayFilterChipRow(
                    descriptors: filter.chips(options: filterOptions),
                    onRemove: { kind in
                        filter.remove(chip: kind)
                    },
                    onClear: { filter.reset() }
                )
            }

            HSplitView {
                activityPane
                    .frame(minWidth: 380, idealWidth: 440, maxWidth: 520)

                debugPane
                    .frame(minWidth: 700, maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $isShowingFilterSheet) {
            RelayFilterSheet(
                filter: $filter,
                options: filterOptions,
                totalLogCount: controller.logEntries.count,
                totalDebugCount: controller.debugEntries.count
            )
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 10) {
            RelayConsoleSearchField(text: $filter.keyword, placeholder: "Search all records · text, path, note, user, model…")
                .frame(minWidth: 280, idealWidth: 420)

            Menu {
                ForEach(RelayTimeRangeFilter.presetCases, id: \.id) { range in
                    Button {
                        filter.timeRange = range
                    } label: {
                        HStack {
                            Text(range.displayName)
                            Spacer()
                            if filter.timeRange == range {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(
                    filter.timeRange == .anytime ? "Any time" : "Time · \(filter.timeRange.shortName)",
                    systemImage: "clock"
                )
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                ForEach(RelayConsoleQuickPreset.standardPresets) { preset in
                    Button {
                        preset.apply(&filter)
                    } label: {
                        Label(preset.title, systemImage: preset.systemImage)
                    }
                }
                Divider()
                Button("Reset all filters", role: .destructive) {
                    filter.reset()
                }
            } label: {
                Label("Quick presets", systemImage: "wand.and.stars")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                isShowingFilterSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                    Text(filter.activeFilterCount > 0 ? "Filters · \(filter.activeFilterCount)" : "Filters")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(filter.activeFilterCount > 0 ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
                )
            }
            .buttonStyle(.plain)

            Spacer()

            Label(
                "\(filteredActivityEntries.count)/\(controller.logEntries.count) activity",
                systemImage: "list.bullet.rectangle"
            )
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)

            Label(
                "\(filteredDebugEntries.count)/\(controller.debugEntries.count) debug",
                systemImage: "ladybug"
            )
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)

            if filter.isActive {
                Button("Clear all") {
                    filter.reset()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Activity pane

    private var activityPane: some View {
        RelayConsolePane {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Activity Stream")
                            .font(.system(size: 22, weight: .bold, design: .rounded))

                        Text("Events are enriched with actor context. Use Filters to slice by user, device, model, or outcome.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Menu {
                        Button {
                            controller.copyToPasteboard(filteredActivityLogText, label: "visible activity log")
                        } label: {
                            Label("Copy visible", systemImage: "doc.on.doc")
                        }
                        .disabled(filteredActivityEntries.isEmpty)

                        Button(role: .destructive) {
                            controller.clearLogEntries()
                        } label: {
                            Label("Clear all", systemImage: "trash")
                        }
                        .disabled(controller.logEntries.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                if filteredActivityEntries.isEmpty {
                    RelayConsoleEmptyState(
                        symbol: controller.logEntries.isEmpty ? "text.badge.xmark" : "line.3.horizontal.decrease.circle",
                        title: controller.logEntries.isEmpty ? "No activity yet" : "No activity matches the filter",
                        message: controller.logEntries.isEmpty
                            ? "Start the relay and send requests to populate the activity stream."
                            : "Widen the search, change the time range, or clear some filters to broaden the result set."
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

    // MARK: - Debug pane

    private var debugPane: some View {
        RelayConsolePane {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Debug Inspector")
                            .font(.system(size: 22, weight: .bold, design: .rounded))

                        Text("Structured request / response traces. Select a row to see headers, body and the resolved actor context.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("Capture debug", isOn: $settings.debugLoggingEnabled)
                        .toggleStyle(.switch)
                        .fixedSize()
                }

                HSplitView {
                    debugListPane
                        .frame(minWidth: 460, idealWidth: 560, maxWidth: 760)

                    debugDetailPane
                        .frame(minWidth: 320, maxWidth: .infinity)
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

                Menu {
                    Button {
                        controller.copyToPasteboard(filteredDebugLogText, label: "visible debug log")
                    } label: {
                        Label("Copy visible", systemImage: "doc.on.doc")
                    }
                    .disabled(filteredDebugEntries.isEmpty)

                    Button(role: .destructive) {
                        controller.clearDebugEntries()
                        selectedDebugEntryID = nil
                    } label: {
                        Label("Clear all", systemImage: "trash")
                    }
                    .disabled(controller.debugEntries.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
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
                        : "Adjust the search text, source or actor filters to broaden the result set."
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

                    TableColumn("Actor") { entry in
                        Text(actorLabel(for: entry.context))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(entry.context?.isEmpty == false ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .width(min: 140, ideal: 160, max: 220)

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
                ScrollView {
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
                            RelayDebugMetadataTile(label: "Actor", value: actorLabel(for: selectedDebugEntry.context))
                        }

                        if let context = selectedDebugEntry.context, context.isEmpty == false {
                            RelayActorContextCard(context: context)
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
                            .frame(minHeight: 220)
                    }
                }
                .scrollContentBackground(.hidden)
            } else {
                RelayConsoleEmptyState(
                    symbol: "sidebar.right",
                    title: "Select a debug record",
                    message: "Choose a row from the debug list to inspect the full request or response payload."
                )
            }
        }
    }

    // MARK: - Helpers

    private var selectedDebugEntry: RelayDebugEntry? {
        guard let selectedDebugEntryID else {
            return nil
        }

        return controller.debugEntries.first(where: { $0.id == selectedDebugEntryID })
    }

    private var filterOptions: RelayConsoleFilterOptions {
        RelayConsoleFilterOptions.build(
            logs: controller.logEntries,
            debug: controller.debugEntries
        )
    }

    private var filteredActivityEntries: [RelayLogEntry] {
        let now = Date()
        return controller.logEntries
            .reversed()
            .filter { filter.matches(activity: $0, now: now) }
    }

    private var filteredDebugEntries: [RelayDebugEntry] {
        let now = Date()
        return controller.debugEntries
            .reversed()
            .filter { filter.matches(debug: $0, now: now) }
    }

    private var filteredActivityLogText: String {
        filteredActivityEntries
            .map { entry in
                let actor = actorLabel(for: entry.context)
                let actorChunk = entry.context?.isEmpty == false ? " actor=\(actor)" : ""
                return "[\(entry.timestamp.formatted(date: .omitted, time: .standard))] \(entry.level.rawValue.uppercased()) [\(entry.category.displayName)]\(actorChunk) \(entry.message)"
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
                    "address=\(entry.address ?? "—")",
                    "actor=\(actorLabel(for: entry.context))"
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

    fileprivate func actorLabel(for context: RelayActorContext?) -> String {
        guard let context, context.isEmpty == false else { return "—" }

        var parts: [String] = []
        if let accountTitle = context.accountDisplayTitle {
            parts.append(accountTitle)
        }
        if let deviceTitle = context.deviceDisplayTitle {
            parts.append("· " + deviceTitle)
        }
        if parts.isEmpty {
            if let model = RelayContextString.trimmedNonEmpty(context.modelID) {
                parts.append(model)
            } else if let keyTitle = context.keyDisplayTitle {
                parts.append(keyTitle)
            }
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Filter sheet

private struct RelayFilterSheet: View {
    @Binding var filter: RelayConsoleFilterState
    let options: RelayConsoleFilterOptions
    let totalLogCount: Int
    let totalDebugCount: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    keywordsSection
                    timeSection
                    activitySection
                    debugSection
                    endpointSection
                    actorSection
                    billingSection
                }
                .padding(24)
            }

            Divider()

            footer
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 560, idealHeight: 720)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Advanced Filters")
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Text("Compose any mix of keyword, time window, severity, operation, status and actor filters. They combine with AND.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label("Scope · \(totalLogCount) activity · \(totalDebugCount) debug", systemImage: "square.stack")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Button("Reset all", role: .destructive) {
                filter.reset()
            }
            .disabled(filter.isActive == false)

            Spacer()

            Text("\(filter.activeFilterCount) active filter\(filter.activeFilterCount == 1 ? "" : "s")")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    // MARK: Sections

    private var keywordsSection: some View {
        RelayFilterSection(title: "Keywords", systemImage: "magnifyingglass", subtitle: "Partial-match search across logs, bodies, and actor metadata.") {
            VStack(alignment: .leading, spacing: 10) {
                RelayFilterLabeledField(label: "Any field", placeholder: "e.g. gemini-3, unauthorized, bearer…", text: $filter.keyword)
                RelayFilterLabeledField(label: "Notes contain", placeholder: "Match account / device / key notes", text: $filter.notesKeyword)
                RelayFilterLabeledField(label: "Remote address contains", placeholder: "e.g. 192.168., fe80:", text: $filter.remoteAddressKeyword)
            }
        }
    }

    private var timeSection: some View {
        RelayFilterSection(title: "Time Range", systemImage: "clock", subtitle: "Restrict visible records to a rolling window or a custom interval.") {
            VStack(alignment: .leading, spacing: 10) {
                FlowLayout(spacing: 8) {
                    ForEach(RelayTimeRangeFilter.presetCases, id: \.id) { range in
                        RelayFilterToggleChip(
                            title: range.displayName,
                            isOn: filter.timeRange == range
                        ) {
                            filter.timeRange = range
                        }
                    }
                }

                if filter.timeRange == .custom {
                    HStack(spacing: 10) {
                        DatePicker("From", selection: $filter.customRangeStart)
                            .labelsHidden()
                        Text("–").foregroundStyle(.secondary)
                        DatePicker("To", selection: $filter.customRangeEnd)
                            .labelsHidden()
                    }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                }
            }
        }
    }

    private var activitySection: some View {
        RelayFilterSection(title: "Activity Stream", systemImage: "list.bullet.rectangle", subtitle: "Controls that only apply to the activity log.") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Severity")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    FlowLayout(spacing: 8) {
                        ForEach(RelayLogLevel.allCases, id: \.self) { level in
                            RelayFilterToggleChip(
                                title: level.displayName,
                                tint: tint(for: level),
                                isOn: filter.severities.contains(level)
                            ) {
                                if filter.severities.contains(level) {
                                    filter.severities.remove(level)
                                } else {
                                    filter.severities.insert(level)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Category")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    FlowLayout(spacing: 8) {
                        ForEach(RelayLogCategory.allCases, id: \.self) { category in
                            RelayFilterToggleChip(
                                title: category.displayName,
                                isOn: filter.categories.contains(category)
                            ) {
                                if filter.categories.contains(category) {
                                    filter.categories.remove(category)
                                } else {
                                    filter.categories.insert(category)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var debugSection: some View {
        RelayFilterSection(title: "Debug Inspector", systemImage: "ladybug", subtitle: "Controls that only apply to the debug table.") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Source")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    FlowLayout(spacing: 8) {
                        ForEach(RelayDebugSource.allCases, id: \.self) { source in
                            RelayFilterToggleChip(
                                title: source.displayName,
                                isOn: filter.debugSources.contains(source)
                            ) {
                                if filter.debugSources.contains(source) {
                                    filter.debugSources.remove(source)
                                } else {
                                    filter.debugSources.insert(source)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Kind")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    FlowLayout(spacing: 8) {
                        ForEach(RelayDebugKind.allCases, id: \.self) { kind in
                            RelayFilterToggleChip(
                                title: kind.displayName,
                                isOn: filter.debugKinds.contains(kind)
                            ) {
                                if filter.debugKinds.contains(kind) {
                                    filter.debugKinds.remove(kind)
                                } else {
                                    filter.debugKinds.insert(kind)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var endpointSection: some View {
        RelayFilterSection(title: "Operation", systemImage: "arrow.triangle.branch", subtitle: "HTTP method, endpoint path, and response status class.") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Status class")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    FlowLayout(spacing: 8) {
                        ForEach(RelayStatusClass.allCases, id: \.self) { bucket in
                            RelayFilterToggleChip(
                                title: bucket.displayName,
                                tint: tint(for: bucket),
                                isOn: filter.statusClasses.contains(bucket)
                            ) {
                                if filter.statusClasses.contains(bucket) {
                                    filter.statusClasses.remove(bucket)
                                } else {
                                    filter.statusClasses.insert(bucket)
                                }
                            }
                        }
                    }
                }

                if options.methods.isEmpty == false {
                    RelayChipMultiPicker(
                        title: "HTTP method",
                        options: options.methods.map { ($0, $0) },
                        selected: Binding(
                            get: { filter.methods },
                            set: { filter.methods = $0 }
                        )
                    )
                } else {
                    RelayFilterPlaceholder(title: "HTTP method", message: "Send a request to populate method options.")
                }

                if options.paths.isEmpty == false {
                    RelayChipMultiPicker(
                        title: "Endpoint path",
                        options: options.paths.map { ($0, $0) },
                        selected: Binding(
                            get: { filter.paths },
                            set: { filter.paths = $0 }
                        )
                    )
                } else {
                    RelayFilterPlaceholder(title: "Endpoint path", message: "No endpoints observed yet.")
                }
            }
        }
    }

    private var actorSection: some View {
        RelayFilterSection(title: "Actor Context", systemImage: "person.crop.rectangle.stack", subtitle: "Filter by the user, device, and key who authenticated each request.") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Context presence")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    FlowLayout(spacing: 8) {
                        ForEach(RelayContextPresenceFilter.allCases, id: \.self) { option in
                            RelayFilterToggleChip(
                                title: option.displayName,
                                isOn: filter.contextPresence == option
                            ) {
                                filter.contextPresence = option
                            }
                        }
                    }
                }

                if options.accounts.isEmpty == false {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Users (\(options.accounts.count))")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(options.accounts) { account in
                                RelayFilterChecklistRow(
                                    title: account.displayName,
                                    subtitle: account.note,
                                    trailing: "\(account.occurrences)",
                                    isOn: filter.accountIDs.contains(account.id)
                                ) {
                                    if filter.accountIDs.contains(account.id) {
                                        filter.accountIDs.remove(account.id)
                                    } else {
                                        filter.accountIDs.insert(account.id)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    RelayFilterPlaceholder(title: "Users", message: "No authenticated traffic recorded yet.")
                }

                if options.devices.isEmpty == false {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Devices (\(options.devices.count))")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(options.devices) { device in
                                RelayFilterChecklistRow(
                                    title: device.displayName,
                                    subtitle: deviceSubtitle(device),
                                    trailing: "\(device.occurrences)",
                                    isOn: filter.deviceIDs.contains(device.id)
                                ) {
                                    if filter.deviceIDs.contains(device.id) {
                                        filter.deviceIDs.remove(device.id)
                                    } else {
                                        filter.deviceIDs.insert(device.id)
                                    }
                                }
                            }
                        }
                    }
                }

                if options.keys.isEmpty == false {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Activation keys (\(options.keys.count))")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(options.keys) { key in
                                RelayFilterChecklistRow(
                                    title: key.displayName,
                                    subtitle: key.note,
                                    trailing: "\(key.occurrences)",
                                    isOn: filter.keyIDs.contains(key.id)
                                ) {
                                    if filter.keyIDs.contains(key.id) {
                                        filter.keyIDs.remove(key.id)
                                    } else {
                                        filter.keyIDs.insert(key.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var billingSection: some View {
        RelayFilterSection(title: "Entitlement", systemImage: "creditcard", subtitle: "Model, device platform, and access source (trial / subscription / offline).") {
            VStack(alignment: .leading, spacing: 14) {
                if options.models.isEmpty == false {
                    RelayChipMultiPicker(
                        title: "Model",
                        options: options.models.map { ($0, $0) },
                        selected: Binding(
                            get: { filter.models },
                            set: { filter.models = $0 }
                        )
                    )
                } else {
                    RelayFilterPlaceholder(title: "Model", message: "Chat or transcription requests will populate this list.")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Access source")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    FlowLayout(spacing: 8) {
                        ForEach(RelayAccessSource.allCases, id: \.self) { source in
                            RelayFilterToggleChip(
                                title: source.rawValue.capitalized,
                                isOn: filter.accessSources.contains(source)
                            ) {
                                if filter.accessSources.contains(source) {
                                    filter.accessSources.remove(source)
                                } else {
                                    filter.accessSources.insert(source)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Device platform")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    FlowLayout(spacing: 8) {
                        ForEach(RelayDevicePlatform.allCases, id: \.self) { platform in
                            RelayFilterToggleChip(
                                title: platform.rawValue,
                                isOn: filter.devicePlatforms.contains(platform)
                            ) {
                                if filter.devicePlatforms.contains(platform) {
                                    filter.devicePlatforms.remove(platform)
                                } else {
                                    filter.devicePlatforms.insert(platform)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func tint(for level: RelayLogLevel) -> Color {
        switch level {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func tint(for bucket: RelayStatusClass) -> Color {
        switch bucket {
        case .informational: return .blue
        case .success: return .green
        case .redirection: return .orange
        case .clientError: return .orange
        case .serverError: return .red
        case .unknown: return .secondary
        }
    }

    private func deviceSubtitle(_ device: RelayDeviceFilterOption) -> String? {
        var bits: [String] = []
        if let platform = device.platform {
            bits.append(platform.rawValue)
        }
        if let note = device.note, note.isEmpty == false {
            bits.append(note)
        }
        bits.append("ID \(RelayContextString.shortID(device.id))")
        return bits.joined(separator: " · ")
    }
}

// MARK: - Filter chip row

private struct RelayFilterChipRow: View {
    let descriptors: [RelayFilterChipDescriptor]
    let onRemove: (RelayFilterChipKind) -> Void
    let onClear: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(descriptors) { descriptor in
                    HStack(spacing: 6) {
                        Image(systemName: descriptor.systemImage)
                            .font(.system(size: 10, weight: .semibold))
                        Text(descriptor.label)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .lineLimit(1)

                        Button {
                            onRemove(descriptor.kind)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(0.15))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 0.8)
                            )
                    )
                }

                Button {
                    onClear()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Filter sheet building blocks

private struct RelayFilterSection<Content: View>: View {
    let title: String
    let systemImage: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }

            Text(subtitle)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

private struct RelayFilterLabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct RelayFilterToggleChip: View {
    let title: String
    var tint: Color = .accentColor
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOn ? tint.opacity(0.2) : Color.primary.opacity(0.05))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(isOn ? tint.opacity(0.55) : Color.primary.opacity(0.12), lineWidth: 1)
                        )
                )
                .foregroundStyle(isOn ? tint : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

private struct RelayChipMultiPicker: View {
    let title: String
    let options: [(key: String, label: String)]
    @Binding var selected: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(title) (\(options.count))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Spacer()
                if selected.isEmpty == false {
                    Button("Clear \(selected.count)") {
                        selected.removeAll()
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.key) { option in
                    RelayFilterToggleChip(
                        title: option.label,
                        isOn: selected.contains(option.key)
                    ) {
                        if selected.contains(option.key) {
                            selected.remove(option.key)
                        } else {
                            selected.insert(option.key)
                        }
                    }
                }
            }
        }
    }
}

private struct RelayFilterChecklistRow: View {
    let title: String
    let subtitle: String?
    let trailing: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.primary)
                    if let subtitle, subtitle.isEmpty == false {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text(trailing)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct RelayFilterPlaceholder: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Text(message)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

// MARK: - Flow layout for chips

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentLineWidth: CGFloat = 0
        var currentLineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentLineWidth + size.width > maxWidth, currentLineWidth > 0 {
                totalHeight += currentLineHeight + spacing
                totalWidth = max(totalWidth, currentLineWidth - spacing)
                currentLineWidth = size.width + spacing
                currentLineHeight = size.height
            } else {
                currentLineWidth += size.width + spacing
                currentLineHeight = max(currentLineHeight, size.height)
            }
        }

        totalHeight += currentLineHeight
        totalWidth = max(totalWidth, currentLineWidth - spacing)
        return CGSize(width: max(0, totalWidth), height: max(0, totalHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Console shell views

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

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(entry.level.rawValue.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(levelTint)

                    Text(entry.category.displayName)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )

                    if let method = entry.method {
                        Text(method)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    if let status = entry.statusCode {
                        Text("\(status)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(statusTint(status))
                    }

                    Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text(entry.message)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)

                if let path = entry.path {
                    Text(path)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let context = entry.context, context.isEmpty == false {
                    HStack(spacing: 6) {
                        if let account = context.accountDisplayTitle {
                            RelayActorInlineChip(systemImage: "person.crop.circle.fill", label: account)
                        }
                        if let device = context.deviceDisplayTitle {
                            RelayActorInlineChip(systemImage: "iphone", label: device)
                        }
                        if let model = RelayContextString.trimmedNonEmpty(context.modelID) {
                            RelayActorInlineChip(systemImage: "sparkles", label: model)
                        }
                    }
                }
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
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func statusTint(_ statusCode: Int) -> Color {
        switch statusCode {
        case 200..<300: return .green
        case 300..<500: return .orange
        default: return .red
        }
    }
}

private struct RelayActorInlineChip: View {
    let systemImage: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(Color.accentColor.opacity(0.14))
        )
        .foregroundStyle(Color.accentColor)
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

private struct RelayActorContextCard: View {
    let context: RelayActorContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.rectangle.stack")
                    .foregroundStyle(Color.accentColor)
                Text("Actor Context")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                if let account = context.accountDisplayTitle {
                    RelayDebugMetadataTile(label: "User", value: account)
                }
                if let note = RelayContextString.trimmedNonEmpty(context.accountNote) {
                    RelayDebugMetadataTile(label: "User note", value: note)
                }
                if let device = context.deviceDisplayTitle {
                    RelayDebugMetadataTile(label: "Device", value: device)
                }
                if let note = RelayContextString.trimmedNonEmpty(context.deviceNote) {
                    RelayDebugMetadataTile(label: "Device note", value: note)
                }
                if let platform = context.devicePlatform {
                    RelayDebugMetadataTile(label: "Platform", value: platform.rawValue)
                }
                if let key = context.keyDisplayTitle {
                    RelayDebugMetadataTile(label: "Key", value: key)
                }
                if let note = RelayContextString.trimmedNonEmpty(context.keyNote) {
                    RelayDebugMetadataTile(label: "Key note", value: note)
                }
                if let model = RelayContextString.trimmedNonEmpty(context.modelID) {
                    RelayDebugMetadataTile(label: "Model", value: model)
                }
                if let source = context.accessSource {
                    RelayDebugMetadataTile(label: "Access source", value: source.rawValue.capitalized)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.25), lineWidth: 0.8)
                )
        )
    }
}
