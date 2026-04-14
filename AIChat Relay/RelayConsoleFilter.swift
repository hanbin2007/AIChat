//
//  RelayConsoleFilter.swift
//  AIChat Relay
//
//  Filter model, predicate engine, and option derivation used by the
//  RelayConsoleWorkspaceView to power multi-dimensional log and debug
//  filtering.
//

import Foundation

// MARK: - Status class (HTTP response grouping)

enum RelayStatusClass: String, CaseIterable, Identifiable, Hashable, Sendable {
    case informational
    case success
    case redirection
    case clientError
    case serverError
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .informational: return "1xx Info"
        case .success: return "2xx Success"
        case .redirection: return "3xx Redirect"
        case .clientError: return "4xx Client Error"
        case .serverError: return "5xx Server Error"
        case .unknown: return "No Status"
        }
    }

    static func classify(_ statusCode: Int?) -> RelayStatusClass {
        guard let statusCode else { return .unknown }
        switch statusCode {
        case 100..<200: return .informational
        case 200..<300: return .success
        case 300..<400: return .redirection
        case 400..<500: return .clientError
        case 500...: return .serverError
        default: return .unknown
        }
    }
}

// MARK: - Time range filter

enum RelayTimeRangeFilter: Hashable, Identifiable, Sendable {
    case anytime
    case lastFiveMinutes
    case lastFifteenMinutes
    case lastHour
    case lastSixHours
    case lastTwentyFourHours
    case today
    case custom

    var id: String {
        switch self {
        case .anytime: return "anytime"
        case .lastFiveMinutes: return "5m"
        case .lastFifteenMinutes: return "15m"
        case .lastHour: return "1h"
        case .lastSixHours: return "6h"
        case .lastTwentyFourHours: return "24h"
        case .today: return "today"
        case .custom: return "custom"
        }
    }

    var displayName: String {
        switch self {
        case .anytime: return "Anytime"
        case .lastFiveMinutes: return "Last 5 minutes"
        case .lastFifteenMinutes: return "Last 15 minutes"
        case .lastHour: return "Last hour"
        case .lastSixHours: return "Last 6 hours"
        case .lastTwentyFourHours: return "Last 24 hours"
        case .today: return "Today"
        case .custom: return "Custom range"
        }
    }

    var shortName: String {
        switch self {
        case .anytime: return "Any time"
        case .lastFiveMinutes: return "5m"
        case .lastFifteenMinutes: return "15m"
        case .lastHour: return "1h"
        case .lastSixHours: return "6h"
        case .lastTwentyFourHours: return "24h"
        case .today: return "Today"
        case .custom: return "Custom"
        }
    }

    static let presetCases: [RelayTimeRangeFilter] = [
        .anytime,
        .lastFiveMinutes,
        .lastFifteenMinutes,
        .lastHour,
        .lastSixHours,
        .lastTwentyFourHours,
        .today,
        .custom
    ]

    func window(now: Date = Date()) -> (start: Date, end: Date)? {
        switch self {
        case .anytime:
            return nil
        case .lastFiveMinutes:
            return (now.addingTimeInterval(-5 * 60), now)
        case .lastFifteenMinutes:
            return (now.addingTimeInterval(-15 * 60), now)
        case .lastHour:
            return (now.addingTimeInterval(-60 * 60), now)
        case .lastSixHours:
            return (now.addingTimeInterval(-6 * 60 * 60), now)
        case .lastTwentyFourHours:
            return (now.addingTimeInterval(-24 * 60 * 60), now)
        case .today:
            let startOfDay = Calendar.current.startOfDay(for: now)
            return (startOfDay, now)
        case .custom:
            return nil
        }
    }
}

// MARK: - Context-presence filter

enum RelayContextPresenceFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case any
    case withActor
    case withoutActor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .any: return "Any actor"
        case .withActor: return "Has actor context"
        case .withoutActor: return "No actor context"
        }
    }
}

// MARK: - Filter option pickables

struct RelayAccountFilterOption: Identifiable, Hashable, Sendable {
    let id: UUID
    let displayName: String
    let note: String?
    let occurrences: Int
}

struct RelayDeviceFilterOption: Identifiable, Hashable, Sendable {
    let id: String
    let alias: String?
    let note: String?
    let platform: RelayDevicePlatform?
    let occurrences: Int

    var displayName: String {
        if let alias, alias.isEmpty == false { return alias }
        return "Device " + RelayContextString.shortID(id)
    }
}

struct RelayKeyFilterOption: Identifiable, Hashable, Sendable {
    let id: UUID
    let note: String?
    let occurrences: Int

    var displayName: String {
        if let note, note.isEmpty == false { return note }
        return "Key " + RelayContextString.shortID(id.uuidString)
    }
}

// MARK: - Filter options (derived from current data)

struct RelayConsoleFilterOptions: Equatable {
    var accounts: [RelayAccountFilterOption]
    var devices: [RelayDeviceFilterOption]
    var keys: [RelayKeyFilterOption]
    var methods: [String]
    var paths: [String]
    var models: [String]
    var remoteAddresses: [String]

    static let empty = RelayConsoleFilterOptions(
        accounts: [],
        devices: [],
        keys: [],
        methods: [],
        paths: [],
        models: [],
        remoteAddresses: []
    )

    static func build(
        logs: [RelayLogEntry],
        debug: [RelayDebugEntry]
    ) -> RelayConsoleFilterOptions {
        var accountAggregator: [UUID: (displayName: String, note: String?, count: Int)] = [:]
        var deviceAggregator: [String: (alias: String?, note: String?, platform: RelayDevicePlatform?, count: Int)] = [:]
        var keyAggregator: [UUID: (note: String?, count: Int)] = [:]
        var methods: Set<String> = []
        var paths: Set<String> = []
        var models: Set<String> = []
        var addresses: Set<String> = []

        func ingestContext(_ context: RelayActorContext?) {
            guard let context else { return }
            if let accountID = context.accountID {
                let existing = accountAggregator[accountID]
                let display = context.accountDisplayTitle ?? "Account " + RelayContextString.shortID(accountID.uuidString)
                accountAggregator[accountID] = (
                    displayName: existing?.displayName ?? display,
                    note: existing?.note ?? RelayContextString.trimmedNonEmpty(context.accountNote),
                    count: (existing?.count ?? 0) + 1
                )
            }
            if let deviceID = context.deviceID, deviceID.isEmpty == false {
                let existing = deviceAggregator[deviceID]
                deviceAggregator[deviceID] = (
                    alias: existing?.alias ?? RelayContextString.trimmedNonEmpty(context.deviceAlias),
                    note: existing?.note ?? RelayContextString.trimmedNonEmpty(context.deviceNote),
                    platform: existing?.platform ?? context.devicePlatform,
                    count: (existing?.count ?? 0) + 1
                )
            }
            if let keyID = context.keyID {
                let existing = keyAggregator[keyID]
                keyAggregator[keyID] = (
                    note: existing?.note ?? RelayContextString.trimmedNonEmpty(context.keyNote),
                    count: (existing?.count ?? 0) + 1
                )
            }
            if let model = RelayContextString.trimmedNonEmpty(context.modelID) {
                models.insert(model)
            }
        }

        func ingest(method: String?, path: String?, remoteAddress: String?) {
            if let method = RelayContextString.trimmedNonEmpty(method) {
                methods.insert(method.uppercased())
            }
            if let path = RelayContextString.trimmedNonEmpty(path) {
                paths.insert(path)
            }
            if let address = RelayContextString.trimmedNonEmpty(remoteAddress) {
                addresses.insert(address)
            }
        }

        for entry in logs {
            ingestContext(entry.context)
            ingest(method: entry.method, path: entry.path, remoteAddress: entry.remoteAddress)
        }
        for entry in debug {
            ingestContext(entry.context)
            ingest(method: entry.method, path: entry.path, remoteAddress: entry.address)
        }

        let accountOptions = accountAggregator
            .map { entry in
                RelayAccountFilterOption(
                    id: entry.key,
                    displayName: entry.value.displayName,
                    note: entry.value.note,
                    occurrences: entry.value.count
                )
            }
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }

        let deviceOptions = deviceAggregator
            .map { entry in
                RelayDeviceFilterOption(
                    id: entry.key,
                    alias: entry.value.alias,
                    note: entry.value.note,
                    platform: entry.value.platform,
                    occurrences: entry.value.count
                )
            }
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }

        let keyOptions = keyAggregator
            .map { entry in
                RelayKeyFilterOption(id: entry.key, note: entry.value.note, occurrences: entry.value.count)
            }
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }

        return RelayConsoleFilterOptions(
            accounts: accountOptions,
            devices: deviceOptions,
            keys: keyOptions,
            methods: methods.sorted(),
            paths: paths.sorted(),
            models: models.sorted(),
            remoteAddresses: addresses.sorted()
        )
    }
}

// MARK: - Filter state

struct RelayConsoleFilterState: Equatable {
    var keyword: String = ""
    var notesKeyword: String = ""
    var remoteAddressKeyword: String = ""

    var severities: Set<RelayLogLevel> = []
    var categories: Set<RelayLogCategory> = []
    var debugSources: Set<RelayDebugSource> = []
    var debugKinds: Set<RelayDebugKind> = []
    var methods: Set<String> = []
    var paths: Set<String> = []
    var models: Set<String> = []
    var statusClasses: Set<RelayStatusClass> = []
    var accountIDs: Set<UUID> = []
    var deviceIDs: Set<String> = []
    var keyIDs: Set<UUID> = []
    var accessSources: Set<RelayAccessSource> = []
    var devicePlatforms: Set<RelayDevicePlatform> = []

    var timeRange: RelayTimeRangeFilter = .anytime
    var customRangeStart: Date = Date().addingTimeInterval(-60 * 60)
    var customRangeEnd: Date = Date()

    var contextPresence: RelayContextPresenceFilter = .any

    static let `default` = RelayConsoleFilterState()

    var isActive: Bool { activeFilterCount > 0 }

    var activeFilterCount: Int {
        var count = 0
        if keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { count += 1 }
        if notesKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { count += 1 }
        if remoteAddressKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { count += 1 }
        if severities.isEmpty == false { count += 1 }
        if categories.isEmpty == false { count += 1 }
        if debugSources.isEmpty == false { count += 1 }
        if debugKinds.isEmpty == false { count += 1 }
        if methods.isEmpty == false { count += 1 }
        if paths.isEmpty == false { count += 1 }
        if models.isEmpty == false { count += 1 }
        if statusClasses.isEmpty == false { count += 1 }
        if accountIDs.isEmpty == false { count += 1 }
        if deviceIDs.isEmpty == false { count += 1 }
        if keyIDs.isEmpty == false { count += 1 }
        if accessSources.isEmpty == false { count += 1 }
        if devicePlatforms.isEmpty == false { count += 1 }
        if timeRange != .anytime { count += 1 }
        if contextPresence != .any { count += 1 }
        return count
    }

    mutating func reset() {
        self = RelayConsoleFilterState()
    }

    /// Range the filter is currently enforcing, if any.
    func activeDateRange(now: Date = Date()) -> (start: Date, end: Date)? {
        switch timeRange {
        case .custom:
            let start = min(customRangeStart, customRangeEnd)
            let end = max(customRangeStart, customRangeEnd)
            return (start, end)
        default:
            return timeRange.window(now: now)
        }
    }

    // MARK: Activity matching

    func matches(activity entry: RelayLogEntry, now: Date = Date()) -> Bool {
        if let range = activeDateRange(now: now) {
            guard entry.timestamp >= range.start && entry.timestamp <= range.end else {
                return false
            }
        }

        if severities.isEmpty == false, severities.contains(entry.level) == false {
            return false
        }

        if categories.isEmpty == false, categories.contains(entry.category) == false {
            return false
        }

        if methods.isEmpty == false {
            guard let method = entry.method?.uppercased(), methods.contains(method) else {
                return false
            }
        }

        if paths.isEmpty == false {
            guard let path = entry.path, paths.contains(path) else {
                return false
            }
        }

        if statusClasses.isEmpty == false {
            let bucket = RelayStatusClass.classify(entry.statusCode)
            guard statusClasses.contains(bucket) else {
                return false
            }
        }

        if matchesActorFilters(context: entry.context) == false {
            return false
        }

        if contextPresence != .any {
            let hasActor = (entry.context?.isEmpty == false)
            if contextPresence == .withActor && hasActor == false { return false }
            if contextPresence == .withoutActor && hasActor { return false }
        }

        if let trimmed = RelayContextString.trimmedNonEmpty(remoteAddressKeyword) {
            let address = entry.remoteAddress?.localizedLowercase ?? ""
            if address.contains(trimmed.localizedLowercase) == false {
                return false
            }
        }

        if let trimmed = RelayContextString.trimmedNonEmpty(notesKeyword) {
            let haystack = (entry.context?.notesBlob ?? "").localizedLowercase
            if haystack.contains(trimmed.localizedLowercase) == false {
                return false
            }
        }

        if let trimmed = RelayContextString.trimmedNonEmpty(keyword) {
            let haystack = activityHaystack(for: entry)
            if haystack.contains(trimmed.localizedLowercase) == false {
                return false
            }
        }

        return true
    }

    // MARK: Debug matching

    func matches(debug entry: RelayDebugEntry, now: Date = Date()) -> Bool {
        if let range = activeDateRange(now: now) {
            guard entry.timestamp >= range.start && entry.timestamp <= range.end else {
                return false
            }
        }

        if debugSources.isEmpty == false, debugSources.contains(entry.source) == false {
            return false
        }

        if debugKinds.isEmpty == false, debugKinds.contains(entry.kind) == false {
            return false
        }

        if methods.isEmpty == false {
            guard let method = entry.method?.uppercased(), methods.contains(method) else {
                return false
            }
        }

        if paths.isEmpty == false {
            guard let path = entry.path, paths.contains(path) else {
                return false
            }
        }

        if statusClasses.isEmpty == false {
            let bucket = RelayStatusClass.classify(entry.statusCode)
            guard statusClasses.contains(bucket) else {
                return false
            }
        }

        if matchesActorFilters(context: entry.context) == false {
            return false
        }

        if contextPresence != .any {
            let hasActor = (entry.context?.isEmpty == false)
            if contextPresence == .withActor && hasActor == false { return false }
            if contextPresence == .withoutActor && hasActor { return false }
        }

        if let trimmed = RelayContextString.trimmedNonEmpty(remoteAddressKeyword) {
            let address = entry.address?.localizedLowercase ?? ""
            if address.contains(trimmed.localizedLowercase) == false {
                return false
            }
        }

        if let trimmed = RelayContextString.trimmedNonEmpty(notesKeyword) {
            let haystack = (entry.context?.notesBlob ?? "").localizedLowercase
            if haystack.contains(trimmed.localizedLowercase) == false {
                return false
            }
        }

        if let trimmed = RelayContextString.trimmedNonEmpty(keyword) {
            let haystack = debugHaystack(for: entry)
            if haystack.contains(trimmed.localizedLowercase) == false {
                return false
            }
        }

        return true
    }

    // MARK: Shared actor filtering

    private func matchesActorFilters(context: RelayActorContext?) -> Bool {
        if accountIDs.isEmpty == false {
            guard let accountID = context?.accountID, accountIDs.contains(accountID) else {
                return false
            }
        }
        if deviceIDs.isEmpty == false {
            guard let deviceID = context?.deviceID, deviceIDs.contains(deviceID) else {
                return false
            }
        }
        if keyIDs.isEmpty == false {
            guard let keyID = context?.keyID, keyIDs.contains(keyID) else {
                return false
            }
        }
        if models.isEmpty == false {
            guard let model = context?.modelID, models.contains(model) else {
                return false
            }
        }
        if accessSources.isEmpty == false {
            guard let source = context?.accessSource, accessSources.contains(source) else {
                return false
            }
        }
        if devicePlatforms.isEmpty == false {
            guard let platform = context?.devicePlatform, devicePlatforms.contains(platform) else {
                return false
            }
        }
        return true
    }

    private func activityHaystack(for entry: RelayLogEntry) -> String {
        [
            entry.level.displayName,
            entry.category.displayName,
            entry.message,
            entry.method ?? "",
            entry.path ?? "",
            entry.remoteAddress ?? "",
            entry.statusCode.map(String.init) ?? "",
            entry.context?.searchHaystack ?? ""
        ]
            .joined(separator: " ")
            .localizedLowercase
    }

    private func debugHaystack(for entry: RelayDebugEntry) -> String {
        [
            entry.title,
            entry.summary,
            entry.source.displayName,
            entry.kind.displayName,
            entry.method ?? "",
            entry.path ?? "",
            entry.address ?? "",
            entry.statusCode.map(String.init) ?? "",
            entry.body,
            entry.context?.searchHaystack ?? ""
        ]
            .joined(separator: " ")
            .localizedLowercase
    }
}

// MARK: - Quick preset definitions

struct RelayConsoleQuickPreset: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let apply: (inout RelayConsoleFilterState) -> Void

    static func == (lhs: RelayConsoleQuickPreset, rhs: RelayConsoleQuickPreset) -> Bool {
        lhs.id == rhs.id
    }

    static let standardPresets: [RelayConsoleQuickPreset] = [
        RelayConsoleQuickPreset(
            id: "errors-only",
            title: "Errors only",
            systemImage: "exclamationmark.triangle.fill"
        ) { state in
            state.severities = [.error]
            state.categories = []
            state.statusClasses = [.clientError, .serverError]
        },
        RelayConsoleQuickPreset(
            id: "warnings-plus",
            title: "Warnings & errors",
            systemImage: "exclamationmark.circle"
        ) { state in
            state.severities = [.warning, .error]
        },
        RelayConsoleQuickPreset(
            id: "successes",
            title: "Successful requests",
            systemImage: "checkmark.seal"
        ) { state in
            state.severities = [.success]
            state.statusClasses = [.success]
            state.categories = [.completed]
        },
        RelayConsoleQuickPreset(
            id: "last-hour",
            title: "Last hour",
            systemImage: "clock.arrow.circlepath"
        ) { state in
            state.timeRange = .lastHour
        },
        RelayConsoleQuickPreset(
            id: "last-5min",
            title: "Last 5 min",
            systemImage: "clock"
        ) { state in
            state.timeRange = .lastFiveMinutes
        },
        RelayConsoleQuickPreset(
            id: "with-actor",
            title: "Has user context",
            systemImage: "person.crop.circle.badge.checkmark"
        ) { state in
            state.contextPresence = .withActor
        },
        RelayConsoleQuickPreset(
            id: "billing-only",
            title: "Billing traffic",
            systemImage: "creditcard"
        ) { state in
            state.categories = [.billing, .usage]
        },
        RelayConsoleQuickPreset(
            id: "chat-streams",
            title: "Chat streams",
            systemImage: "bubble.left.and.bubble.right"
        ) { state in
            state.paths = ["/v1/chat/stream"]
        },
        RelayConsoleQuickPreset(
            id: "anonymous",
            title: "Anonymous traffic",
            systemImage: "person.crop.circle.badge.questionmark"
        ) { state in
            state.contextPresence = .withoutActor
        }
    ]
}

// MARK: - Active filter chip descriptor

enum RelayFilterChipKind: Hashable {
    case keyword
    case notesKeyword
    case remoteAddressKeyword
    case severity(RelayLogLevel)
    case category(RelayLogCategory)
    case debugSource(RelayDebugSource)
    case debugKind(RelayDebugKind)
    case method(String)
    case path(String)
    case model(String)
    case statusClass(RelayStatusClass)
    case account(UUID)
    case device(String)
    case key(UUID)
    case accessSource(RelayAccessSource)
    case devicePlatform(RelayDevicePlatform)
    case timeRange
    case contextPresence
}

struct RelayFilterChipDescriptor: Identifiable, Hashable {
    let id: String
    let kind: RelayFilterChipKind
    let systemImage: String
    let label: String
}

extension RelayConsoleFilterState {
    /// Render the state as chip descriptors so the UI can display them and
    /// allow per-filter removal. The options argument provides nicer display
    /// names for accounts / devices / keys (fallbacks to short IDs otherwise).
    func chips(options: RelayConsoleFilterOptions) -> [RelayFilterChipDescriptor] {
        var result: [RelayFilterChipDescriptor] = []

        let keywordTrimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if keywordTrimmed.isEmpty == false {
            result.append(RelayFilterChipDescriptor(
                id: "kw",
                kind: .keyword,
                systemImage: "magnifyingglass",
                label: "Search: \"\(keywordTrimmed)\""
            ))
        }

        let notesTrimmed = notesKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if notesTrimmed.isEmpty == false {
            result.append(RelayFilterChipDescriptor(
                id: "notes",
                kind: .notesKeyword,
                systemImage: "note.text",
                label: "Notes contain: \"\(notesTrimmed)\""
            ))
        }

        let addrTrimmed = remoteAddressKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if addrTrimmed.isEmpty == false {
            result.append(RelayFilterChipDescriptor(
                id: "addr",
                kind: .remoteAddressKeyword,
                systemImage: "network",
                label: "Address: \"\(addrTrimmed)\""
            ))
        }

        if timeRange != .anytime {
            let label: String
            switch timeRange {
            case .custom:
                let df = DateFormatter()
                df.dateStyle = .short
                df.timeStyle = .short
                let start = min(customRangeStart, customRangeEnd)
                let end = max(customRangeStart, customRangeEnd)
                label = "Time: \(df.string(from: start)) – \(df.string(from: end))"
            default:
                label = "Time: \(timeRange.shortName)"
            }
            result.append(RelayFilterChipDescriptor(
                id: "time",
                kind: .timeRange,
                systemImage: "clock",
                label: label
            ))
        }

        if contextPresence != .any {
            result.append(RelayFilterChipDescriptor(
                id: "actor-pres",
                kind: .contextPresence,
                systemImage: "person.crop.circle",
                label: contextPresence.displayName
            ))
        }

        for level in severities.sorted(by: { $0.rawValue < $1.rawValue }) {
            result.append(RelayFilterChipDescriptor(
                id: "sev-\(level.rawValue)",
                kind: .severity(level),
                systemImage: "bolt.circle",
                label: "Severity: \(level.displayName)"
            ))
        }

        for category in categories.sorted(by: { $0.rawValue < $1.rawValue }) {
            result.append(RelayFilterChipDescriptor(
                id: "cat-\(category.rawValue)",
                kind: .category(category),
                systemImage: "square.stack.3d.up",
                label: "Category: \(category.displayName)"
            ))
        }

        for source in debugSources.sorted(by: { $0.rawValue < $1.rawValue }) {
            result.append(RelayFilterChipDescriptor(
                id: "src-\(source.rawValue)",
                kind: .debugSource(source),
                systemImage: "shippingbox",
                label: "Source: \(source.displayName)"
            ))
        }

        for kind in debugKinds.sorted(by: { $0.rawValue < $1.rawValue }) {
            result.append(RelayFilterChipDescriptor(
                id: "kind-\(kind.rawValue)",
                kind: .debugKind(kind),
                systemImage: "scribble",
                label: "Kind: \(kind.displayName)"
            ))
        }

        for method in methods.sorted() {
            result.append(RelayFilterChipDescriptor(
                id: "method-\(method)",
                kind: .method(method),
                systemImage: "arrow.right.arrow.left",
                label: "Method: \(method)"
            ))
        }

        for path in paths.sorted() {
            result.append(RelayFilterChipDescriptor(
                id: "path-\(path)",
                kind: .path(path),
                systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                label: "Path: \(path)"
            ))
        }

        for model in models.sorted() {
            result.append(RelayFilterChipDescriptor(
                id: "model-\(model)",
                kind: .model(model),
                systemImage: "sparkles",
                label: "Model: \(model)"
            ))
        }

        for bucket in statusClasses.sorted(by: { $0.rawValue < $1.rawValue }) {
            result.append(RelayFilterChipDescriptor(
                id: "status-\(bucket.rawValue)",
                kind: .statusClass(bucket),
                systemImage: "number.circle",
                label: "Status: \(bucket.displayName)"
            ))
        }

        for accountID in accountIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            let display = options.accounts.first(where: { $0.id == accountID })?.displayName
                ?? ("Account " + RelayContextString.shortID(accountID.uuidString))
            result.append(RelayFilterChipDescriptor(
                id: "acct-\(accountID.uuidString)",
                kind: .account(accountID),
                systemImage: "person.crop.circle.fill",
                label: "User: \(display)"
            ))
        }

        for deviceID in deviceIDs.sorted() {
            let display = options.devices.first(where: { $0.id == deviceID })?.displayName
                ?? ("Device " + RelayContextString.shortID(deviceID))
            result.append(RelayFilterChipDescriptor(
                id: "dev-\(deviceID)",
                kind: .device(deviceID),
                systemImage: "iphone",
                label: "Device: \(display)"
            ))
        }

        for keyID in keyIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            let display = options.keys.first(where: { $0.id == keyID })?.displayName
                ?? ("Key " + RelayContextString.shortID(keyID.uuidString))
            result.append(RelayFilterChipDescriptor(
                id: "key-\(keyID.uuidString)",
                kind: .key(keyID),
                systemImage: "key",
                label: "Key: \(display)"
            ))
        }

        for source in accessSources.sorted(by: { $0.rawValue < $1.rawValue }) {
            result.append(RelayFilterChipDescriptor(
                id: "access-\(source.rawValue)",
                kind: .accessSource(source),
                systemImage: "ticket",
                label: "Access: \(source.rawValue.capitalized)"
            ))
        }

        for platform in devicePlatforms.sorted(by: { $0.rawValue < $1.rawValue }) {
            result.append(RelayFilterChipDescriptor(
                id: "platform-\(platform.rawValue)",
                kind: .devicePlatform(platform),
                systemImage: "square.on.square",
                label: "Platform: \(platform.rawValue)"
            ))
        }

        return result
    }

    mutating func remove(chip: RelayFilterChipKind) {
        switch chip {
        case .keyword:
            keyword = ""
        case .notesKeyword:
            notesKeyword = ""
        case .remoteAddressKeyword:
            remoteAddressKeyword = ""
        case .severity(let level):
            severities.remove(level)
        case .category(let category):
            categories.remove(category)
        case .debugSource(let source):
            debugSources.remove(source)
        case .debugKind(let kind):
            debugKinds.remove(kind)
        case .method(let method):
            methods.remove(method)
        case .path(let path):
            paths.remove(path)
        case .model(let model):
            models.remove(model)
        case .statusClass(let bucket):
            statusClasses.remove(bucket)
        case .account(let id):
            accountIDs.remove(id)
        case .device(let id):
            deviceIDs.remove(id)
        case .key(let id):
            keyIDs.remove(id)
        case .accessSource(let source):
            accessSources.remove(source)
        case .devicePlatform(let platform):
            devicePlatforms.remove(platform)
        case .timeRange:
            timeRange = .anytime
        case .contextPresence:
            contextPresence = .any
        }
    }
}
