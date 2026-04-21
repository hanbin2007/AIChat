//
//  ConversationListView.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import SwiftUI

#if os(watchOS)
struct ConversationListView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Binding var navigationPath: [UUID]
    @State private var isShowingActivationCenter = false
    @State private var visibleConversationLimit = 0
    @State private var visibleConversationEntries: [IndexedConversationListItem] = []
    @State private var isLoadingMoreConversations = false
    @State private var paginationTask: Task<Void, Never>?

    private static let initialPageSize = 3
    private static let incrementalPageSize = 3
    private static let preloadThreshold = 2
    private static let paginationLoadDelayNanoseconds: UInt64 = 16_000_000

    init(
        navigationPath: Binding<[UUID]>,
        initialVisibleConversationLimit: Int = 0
    ) {
        self._navigationPath = navigationPath
        self._visibleConversationLimit = State(initialValue: initialVisibleConversationLimit)
    }

    var body: some View {
        WatchMinuteRelativeTimeline { relativeNow in
            ZStack {
                AppBackdropView()

                List {
                    ActivationStatusCard(
                        title: chatStore.activationStatusTitle,
                        message: chatStore.activationStatusMessage,
                        iconName: chatStore.isReadOnlyMode ? "lock.fill" : "checkmark.seal.fill",
                        accentColor: chatStore.isReadOnlyMode ? .orange : .green,
                        actionTitle: chatStore.isReadOnlyMode ? "立即激活" : "管理授权"
                    ) {
                        isShowingActivationCenter = true
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)

                    if chatStore.configuration.isAIConfigured == false {
                        ConfigurationBannerView(message: chatStore.configuration.configurationMessage)
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                    }

                    ConfigurationBannerView(
                        iconName: "network",
                        title: chatStore.configuration.backendSummary,
                        message: "\(chatStore.storageDescription) • \(chatStore.syncStatusDescription)"
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)

                    if let startupError = chatStore.startupError {
                        ConfigurationBannerView(
                            iconName: "exclamationmark.triangle.fill",
                            title: "Storage Error",
                            message: startupError
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                    }

                    if chatStore.conversationListItems.isEmpty {
                        if chatStore.isInitialConversationLoadInProgress && chatStore.startupError == nil {
                            initialLoadingState
                                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                                .listRowBackground(Color.clear)
                        } else {
                            emptyState
                                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                                .listRowBackground(Color.clear)
                        }
                    } else {
                        ForEach(visibleConversationEntries) { entry in
                            NavigationLink(value: entry.item.id) {
                                ConversationRowView(
                                    item: entry.item,
                                    relativeNow: relativeNow
                                )
                                .equatable()
                            }
                            .accessibilityIdentifier("conversation.row.\(entry.item.id.uuidString)")
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                favoriteSwipeAction(for: entry.item)
                                deleteSwipeAction(for: entry.item)
                            }
                            .onAppear {
                                scheduleLoadMoreConversationsIfNeeded(currentIndex: entry.index)
                            }
                        }

                        if isLoadingMoreConversations {
                            paginationLoadingRow
                                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 10, trailing: 0))
                                .listRowBackground(Color.clear)
                                .onAppear {
                                    scheduleLoadMoreConversations(force: true)
                                }
                        }
                    }
                }
                .accessibilityIdentifier("conversation.list")
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .animation(nil, value: visibleConversationLimit)
                .overlay(alignment: .topLeading) {
                    if chatStore.isInitialConversationLoadInProgress,
                       chatStore.conversationListItems.isEmpty,
                       chatStore.startupError == nil {
                        Text("Loading conversations")
                            .font(.system(size: 1))
                            .foregroundStyle(.clear)
                            .frame(width: 1, height: 1)
                            .allowsHitTesting(false)
                            .accessibilityIdentifier("conversation.list.initial-loading.marker")
                    }
                }
            }
        }
        .onAppear {
            resetVisibleConversationLimitIfNeeded()
            replaceVisibleConversationEntries()
        }
        .onChange(of: chatStore.conversationListItems) { oldValue, newValue in
            syncVisibleConversationEntries(previousItems: oldValue, newItems: newValue)
        }
        .onDisappear {
            paginationTask?.cancel()
            paginationTask = nil
            isLoadingMoreConversations = false
        }
        .sheet(isPresented: $isShowingActivationCenter) {
            ActivationCenterView()
        }
    }

    private var paginationLoadingRow: some View {
        HStack {
            Spacer(minLength: 0)

            ProgressView()
                .controlSize(.small)
                .tint(.cyan)
                .accessibilityIdentifier("conversation.list.loading")

            Spacer(minLength: 0)
        }
    }

    private var initialLoadingState: some View {
        HStack {
            Spacer(minLength: 0)

            ProgressView()
                .controlSize(.regular)
                .tint(.cyan)
                .accessibilityIdentifier("conversation.list.initial-loading.spinner")

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Built for Watch")
                .font(.headline)

            Text(
                chatStore.isReadOnlyMode ?
                "你现在可以查看历史消息。完成手表离线激活后，才能开始新会话并发送消息。" :
                "Context-aware Gemini chat, voice prompts, photo prompts, streaming replies, relay-ready networking, and sync scaffolding for a paired iPhone."
            )
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                if chatStore.isReadOnlyMode {
                    isShowingActivationCenter = true
                } else {
                    Task {
                        if let newConversationID = await chatStore.createConversation() {
                            navigationPath = [newConversationID]
                        }
                    }
                }
            } label: {
                Label(
                    chatStore.isReadOnlyMode ? "Activate Watch" : "Start Chat",
                    systemImage: chatStore.isReadOnlyMode ? "key.fill" : "sparkles"
                )
                    .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("conversation.empty.primary")
            .buttonStyle(.borderedProminent)
            .tint(chatStore.isReadOnlyMode ? .orange : .cyan)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.42))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conversation.empty-state")
    }

    @ViewBuilder
    private func favoriteSwipeAction(for item: WatchConversationListItem) -> some View {
        Button {
            Task {
                await chatStore.setConversationFavorite(item.isFavorite == false, for: item.id)
            }
        } label: {
            Label(
                item.isFavorite ? L10n.tr("favorites.remove") : L10n.tr("favorites.add"),
                systemImage: item.isFavorite ? "star.slash" : "star"
            )
        }
        .tint(item.isFavorite ? .orange : .yellow)
    }

    @ViewBuilder
    private func deleteSwipeAction(for item: WatchConversationListItem) -> some View {
        Button(role: .destructive) {
            Task {
                await chatStore.deleteConversation(id: item.id)
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .accessibilityIdentifier("conversation.delete.\(item.id.uuidString)")
    }

    private func resetVisibleConversationLimitIfNeeded() {
        guard visibleConversationLimit == 0 else {
            return
        }

        visibleConversationLimit = min(Self.initialPageSize, chatStore.conversationListItems.count)
    }

    private func syncVisibleConversationEntries(
        previousItems: [WatchConversationListItem],
        newItems: [WatchConversationListItem]
    ) {
        guard previousItems != newItems else {
            return
        }

        let newCount = newItems.count
        guard newCount > 0 else {
            visibleConversationLimit = 0
            visibleConversationEntries = []
            isLoadingMoreConversations = false
            paginationTask?.cancel()
            paginationTask = nil
            return
        }

        let minimumVisible = min(Self.initialPageSize, newCount)
        if visibleConversationLimit == 0 {
            visibleConversationLimit = minimumVisible
            isLoadingMoreConversations = false
            replaceVisibleConversationEntries(using: newItems)
            return
        }

        visibleConversationLimit = min(max(visibleConversationLimit, minimumVisible), newCount)
        replaceVisibleConversationEntries(using: newItems)
        if visibleConversationLimit >= newCount {
            isLoadingMoreConversations = false
            paginationTask?.cancel()
            paginationTask = nil
        }
    }

    private func scheduleLoadMoreConversationsIfNeeded(currentIndex: Int) {
        guard visibleConversationEntries.count < chatStore.conversationListItems.count else {
            return
        }

        let triggerIndex = max(visibleConversationEntries.count - Self.preloadThreshold, 0)
        guard currentIndex >= triggerIndex else {
            return
        }

        scheduleLoadMoreConversations()
    }

    private func scheduleLoadMoreConversations(force: Bool = false) {
        guard visibleConversationEntries.count < chatStore.conversationListItems.count else {
            isLoadingMoreConversations = false
            paginationTask?.cancel()
            paginationTask = nil
            return
        }

        guard force || isLoadingMoreConversations == false else {
            return
        }

        guard paginationTask == nil else {
            return
        }

        let nextLimit = min(
            visibleConversationEntries.count + Self.incrementalPageSize,
            chatStore.conversationListItems.count
        )

        isLoadingMoreConversations = true
        paginationTask = Task(priority: .utility) {
            await Task.yield()
            try? await Task.sleep(nanoseconds: Self.paginationLoadDelayNanoseconds)
            guard Task.isCancelled == false else {
                return
            }

            await MainActor.run {
                appendVisibleConversationEntries(upTo: nextLimit)
                isLoadingMoreConversations = false
                paginationTask = nil
            }
        }
    }

    private func replaceVisibleConversationEntries(
        using items: [WatchConversationListItem]? = nil
    ) {
        let sourceItems = items ?? chatStore.conversationListItems
        let clampedLimit = min(visibleConversationLimit, sourceItems.count)
        visibleConversationLimit = clampedLimit

        var updatedEntries: [IndexedConversationListItem] = []
        updatedEntries.reserveCapacity(clampedLimit)

        for index in 0..<clampedLimit {
            updatedEntries.append(
                IndexedConversationListItem(
                    index: index,
                    item: sourceItems[index]
                )
            )
        }

        if visibleConversationEntries != updatedEntries {
            visibleConversationEntries = updatedEntries
        }
    }

    private func appendVisibleConversationEntries(upTo targetLimit: Int) {
        let sourceItems = chatStore.conversationListItems
        let startIndex = visibleConversationEntries.count
        let clampedTargetLimit = min(targetLimit, sourceItems.count)

        guard clampedTargetLimit > startIndex else {
            visibleConversationLimit = clampedTargetLimit
            return
        }

        var appendedEntries: [IndexedConversationListItem] = []
        appendedEntries.reserveCapacity(clampedTargetLimit - startIndex)

        for index in startIndex..<clampedTargetLimit {
            appendedEntries.append(
                IndexedConversationListItem(
                    index: index,
                    item: sourceItems[index]
                )
            )
        }

        visibleConversationLimit = clampedTargetLimit
        visibleConversationEntries.append(contentsOf: appendedEntries)
    }
}
#endif

private struct IndexedConversationListItem: Identifiable, Equatable {
    let index: Int
    let item: WatchConversationListItem

    var id: UUID { item.id }
}

struct ConversationRowView: View, Equatable {
    let item: WatchConversationListItem
    let relativeNow: Date

    static func == (lhs: ConversationRowView, rhs: ConversationRowView) -> Bool {
        lhs.rowSignature == rhs.rowSignature
    }

    private var rowSignature: WatchConversationRowSignature {
        WatchConversationRowSignature(
            item: item,
            relativeTimestampDescriptor: WatchRelativeTimestampText.descriptor(
                for: item.updatedAt,
                relativeTo: relativeNow
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)

                if item.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }

                Spacer(minLength: 4)

                WatchRelativeTimestampText(
                    updatedAt: item.updatedAt,
                    referenceDate: relativeNow
                )
            }

            Text(item.previewText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            ViewThatFits(in: .horizontal) {
                metaLine(includeAttachments: true, includeThinking: true)
                metaLine(includeAttachments: false, includeThinking: true)
                metaLine(includeAttachments: false, includeThinking: false)
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.cyan.opacity(0.9))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.38))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        // Conversation titles + preview snippets are user-authored content
        // and can leak secrets on AOD. Redact the whole row (including the
        // meta line) via `.privacySensitive()`; meta is boring icons+counts
        // but a blanket modifier is safer than a partial one. Applied here so
        // both `ConversationListView` and `FavoritesView` inherit the rule.
        .privacySensitive()
    }

    @ViewBuilder
    private func metaLine(
        includeAttachments: Bool,
        includeThinking: Bool
    ) -> some View {
        HStack(spacing: 5) {
            WatchConversationMetaItem(
                iconName: "bubble.left.and.bubble.right",
                title: "\(item.messageCount)"
            )

            if includeAttachments, item.containsAudioAttachments {
                WatchConversationMetaItem(iconName: "waveform")
            }

            if includeAttachments, item.containsImageAttachments {
                WatchConversationMetaItem(iconName: "photo")
            }

            WatchConversationMetaItem(
                iconName: "cpu",
                title: item.modelShortLabel
            )

            if includeThinking {
                WatchConversationMetaItem(
                    iconName: "brain.head.profile",
                    title: item.thinkingShortLabel
                )
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.9)
    }
}

private struct WatchConversationRowSignature: Equatable {
    let item: WatchConversationListItem
    let relativeTimestampDescriptor: WatchRelativeTimestampText.Descriptor
}

private struct WatchConversationMetaItem: View {
    let iconName: String
    var title: String? = nil

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: iconName)
                .imageScale(.small)

            if let title {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .monospacedDigit()
            }
        }
    }
}

private struct WatchRelativeTimestampText: View {
    struct Descriptor: Equatable {
        enum Unit: Equatable {
            case justNow
            case minute
            case hour
            case day
            case week
            case month
            case year
        }

        let unit: Unit
        let value: Int
    }

    let updatedAt: Date
    let referenceDate: Date

    var body: some View {
        let descriptor = Self.descriptor(for: updatedAt, relativeTo: referenceDate)

        Text(Self.label(for: descriptor, locale: .autoupdatingCurrent))
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    static func nextMinuteBoundary(after date: Date) -> Date {
        let calendar = Calendar.autoupdatingCurrent
        return calendar.nextDate(
            after: date,
            matching: DateComponents(second: 0),
            matchingPolicy: .nextTime
        ) ?? date.addingTimeInterval(60)
    }

    static func descriptor(for updatedAt: Date, relativeTo now: Date) -> Descriptor {
        guard updatedAt <= now else {
            return Descriptor(unit: .justNow, value: 0)
        }

        let calendar = Calendar.autoupdatingCurrent

        let components = calendar.dateComponents(
            [.year, .month, .weekOfMonth, .day, .hour, .minute],
            from: updatedAt,
            to: now
        )

        if let years = components.year, years > 0 {
            return Descriptor(unit: .year, value: years)
        }

        if let months = components.month, months > 0 {
            return Descriptor(unit: .month, value: months)
        }

        if let weeks = components.weekOfMonth, weeks > 0 {
            return Descriptor(unit: .week, value: weeks)
        }

        if let days = components.day, days > 0 {
            return Descriptor(unit: .day, value: days)
        }

        if let hours = components.hour, hours > 0 {
            return Descriptor(unit: .hour, value: hours)
        }

        if let minutes = components.minute, minutes > 0 {
            return Descriptor(unit: .minute, value: minutes)
        }

        return Descriptor(unit: .justNow, value: 0)
    }

    static func label(for updatedAt: Date, relativeTo now: Date) -> String {
        label(
            for: descriptor(for: updatedAt, relativeTo: now),
            locale: .autoupdatingCurrent
        )
    }

    static func label(for descriptor: Descriptor, locale: Locale) -> String {
        let isChinese = locale.identifier.hasPrefix("zh")

        switch descriptor.unit {
        case .justNow:
            return justNowLabel(for: locale)
        case .minute:
            return isChinese ? "\(descriptor.value) 分钟前" : "\(descriptor.value)m ago"
        case .hour:
            return isChinese ? "\(descriptor.value) 小时前" : "\(descriptor.value)h ago"
        case .day:
            return isChinese ? "\(descriptor.value) 天前" : "\(descriptor.value)d ago"
        case .week:
            return isChinese ? "\(descriptor.value) 周前" : "\(descriptor.value)w ago"
        case .month:
            return isChinese ? "\(descriptor.value) 个月前" : "\(descriptor.value)mo ago"
        case .year:
            return isChinese ? "\(descriptor.value) 年前" : "\(descriptor.value)y ago"
        }
    }

    private static func justNowLabel(for locale: Locale) -> String {
        locale.identifier.hasPrefix("zh") ? "刚刚" : "Just now"
    }
}

struct WatchMinuteRelativeTimeline<Content: View>: View {
    let content: (Date) -> Content

    init(@ViewBuilder content: @escaping (Date) -> Content) {
        self.content = content
    }

    var body: some View {
        TimelineView(.periodic(from: WatchRelativeTimestampText.nextMinuteBoundary(after: .now), by: 60)) { context in
            content(context.date)
        }
    }
}
