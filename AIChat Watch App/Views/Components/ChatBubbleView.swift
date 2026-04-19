//
//  ChatBubbleView.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import SwiftUI
#if os(watchOS)
import WatchKit
#endif

private enum MessageBubbleInteraction {
    static let actionsLongPressDuration = 0.35
    static let actionsLongPressMaximumDistance: CGFloat = 4
}

struct ChatBubbleView: View, Equatable {
    let conversationID: UUID
    let message: ChatMessage
    let suspendStreamingRender: Bool
    let forceExpandedContent: Bool
    let isLatestReplyAnchorTarget: Bool
    /// Scoped publisher for streaming text reveal. Only the currently-streaming
    /// bubble subscribes to it (via `StreamingAssistantBodyView`) so other
    /// bubbles and the surrounding detail view stay untouched per-token.
    let streamingPacer: StreamingTextPacer?
    var onPinMessage: ((UUID, UUID, PinnedMemoryScope) async -> Void)?

    @State private var isShowingMessageActions = false
    @State private var didTriggerStreamingStartHaptics = false
    @State private var didTriggerStreamingBodyHaptics = false
    @State private var didTriggerReplyCompletionHaptic = false
    @State private var renderedText: String
    @State private var renderedThoughtSummary: String?
    #if os(watchOS)
    @State private var replyHapticTask: Task<Void, Never>?
    #endif

    init(
        conversationID: UUID,
        message: ChatMessage,
        suspendStreamingRender: Bool = false,
        forceExpandedContent: Bool = false,
        isLatestReplyAnchorTarget: Bool = false,
        streamingPacer: StreamingTextPacer? = nil,
        onPinMessage: ((UUID, UUID, PinnedMemoryScope) async -> Void)? = nil
    ) {
        self.conversationID = conversationID
        self.message = message
        self.suspendStreamingRender = suspendStreamingRender
        self.forceExpandedContent = forceExpandedContent
        self.isLatestReplyAnchorTarget = isLatestReplyAnchorTarget
        self.streamingPacer = streamingPacer
        self.onPinMessage = onPinMessage
        _renderedText = State(initialValue: message.cleanedText)
        _renderedThoughtSummary = State(initialValue: message.cleanedThoughtSummary)
    }

    private var isUser: Bool {
        message.role == .user
    }

    private var isStreamingAssistant: Bool {
        isUser == false && message.status == .streaming
    }

    private var isStreamingPaused: Bool {
        isStreamingAssistant && suspendStreamingRender
    }

    private var displayedText: String {
        renderedText
    }

    private var displayedThoughtSummary: String? {
        renderedThoughtSummary
    }

    private var hasReceivedStreamingChunk: Bool {
        isStreamingAssistant &&
        (displayedText.isEmpty == false || displayedThoughtSummary != nil)
    }

    private var hasStartedStreamingBodyText: Bool {
        isStreamingAssistant && displayedText.isEmpty == false
    }

    private var allowsLiveStreamingRender: Bool {
        suspendStreamingRender == false || message.status != .streaming
    }

    private var canPinMessage: Bool {
        displayedText.isEmpty == false
    }

    private var bubbleShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }

    private var messageBodyAccessibilityIdentifier: String {
        "conversation.message.body.\(message.id.uuidString.lowercased())"
    }

    private var messageExpandButtonAccessibilityIdentifier: String {
        "conversation.message.expand.\(message.id.uuidString.lowercased())"
    }

    private var thoughtSummaryToggleAccessibilityIdentifier: String {
        "conversation.message.thought-summary.toggle.\(message.id.uuidString.lowercased())"
    }

    private var thoughtSummaryStateAccessibilityIdentifier: String {
        "conversation.message.thought-summary.state.\(message.id.uuidString.lowercased())"
    }

    private var latestReplyStartAnchorID: String {
        "conversation-latest-reply-start-anchor"
    }

    private var latestReplyStartAccessibilityIdentifier: String {
        "conversation.latest.reply.start"
    }

    static func == (lhs: ChatBubbleView, rhs: ChatBubbleView) -> Bool {
        lhs.conversationID == rhs.conversationID &&
        lhs.message.renderSignature == rhs.message.renderSignature &&
        lhs.suspendStreamingRender == rhs.suspendStreamingRender &&
        lhs.forceExpandedContent == rhs.forceExpandedContent &&
        lhs.isLatestReplyAnchorTarget == rhs.isLatestReplyAnchorTarget
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isUser {
                Spacer(minLength: 24)
            }

            bubbleContent
                .frame(maxWidth: isUser ? nil : .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .onAppear {
            if hasReceivedStreamingChunk {
                triggerStreamingStartHapticsIfNeeded()
            }

            if hasStartedStreamingBodyText {
                triggerStreamingBodyHapticsIfNeeded()
            }
        }
        .compatibleOnChange(of: message.id) { _ in
            syncRenderedContent()
            resetStreamingHaptics()
        }
        .compatibleOnChange(of: message.text) { _ in
            syncRenderedContentIfNeeded()
        }
        .compatibleOnChange(of: message.thoughtSummary) { _ in
            syncRenderedContentIfNeeded()
        }
        .compatibleOnChange(of: message.modelResponseParts) { _ in
            syncRenderedContentIfNeeded()
        }
        .compatibleOnChange(of: message.status) { _ in
            syncRenderedContent()
        }
        .compatibleOnChange(of: suspendStreamingRender) { isSuspended in
            guard isSuspended == false else {
                return
            }

            syncRenderedContent()
        }
        .compatibleOnChange(of: hasReceivedStreamingChunk) { hasReceivedChunk in
            guard hasReceivedChunk else {
                return
            }

            triggerStreamingStartHapticsIfNeeded()
        }
        .compatibleOnChange(of: hasStartedStreamingBodyText) { hasStartedBodyText in
            guard hasStartedBodyText else {
                return
            }

            triggerStreamingBodyHapticsIfNeeded()
        }
        .compatibleOnChange(of: message.status) { status in
            handleAssistantStatusChange(status)
        }
        .onDisappear {
            cancelReplyHaptics()
        }
    }

    private var bubbleContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if message.attachments.isEmpty == false {
                AttachmentGridView(attachments: message.attachments)
            }

            if isStreamingAssistant, let pacer = streamingPacer {
                // Pacer-scoped rendering. Only this subtree reacts to
                // per-token reveal; ChatBubbleView itself does not subscribe.
                // Fallbacks are the @State `renderedText` / `renderedThoughtSummary`
                // which track `message.text` via `.compatibleOnChange`. If this
                // bubble is NOT the pacer's current target (i.e. user has a
                // second stream running in another conversation), those
                // fallbacks render the last-checkpointed text instead of
                // blanking — critical for the multi-stream navigation case.
                StreamingAssistantBodyView(
                    pacer: pacer,
                    messageID: message.id,
                    fallbackText: renderedText,
                    fallbackThoughtSummary: renderedThoughtSummary,
                    forceExpandedContent: forceExpandedContent,
                    isLatestReplyAnchorTarget: isLatestReplyAnchorTarget,
                    thoughtSummaryToggleAccessibilityIdentifier: thoughtSummaryToggleAccessibilityIdentifier,
                    thoughtSummaryStateAccessibilityIdentifier: thoughtSummaryStateAccessibilityIdentifier,
                    messageBodyAccessibilityIdentifier: messageBodyAccessibilityIdentifier,
                    expandButtonAccessibilityIdentifier: messageExpandButtonAccessibilityIdentifier,
                    latestReplyStartAnchorID: latestReplyStartAnchorID,
                    latestReplyStartAccessibilityIdentifier: latestReplyStartAccessibilityIdentifier
                )
            } else {
                if isUser == false, let thoughtSummary = displayedThoughtSummary {
                    ThoughtSummaryCard(
                        thoughtSummary: thoughtSummary,
                        isStreaming: message.status == .streaming,
                        toggleAccessibilityIdentifier: thoughtSummaryToggleAccessibilityIdentifier,
                        stateAccessibilityIdentifier: thoughtSummaryStateAccessibilityIdentifier
                    )
                }

                if message.status == .failed, displayedText.isEmpty {
                    Text("Stopped")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                } else if displayedText.isEmpty == false {
                    if isUser == false, isLatestReplyAnchorTarget {
                        MessageAnchorMarker(
                            anchorID: latestReplyStartAnchorID,
                            accessibilityIdentifier: latestReplyStartAccessibilityIdentifier
                        )
                    }

                    messageTextContent
                }
            }

            if isStreamingAssistant {
                StreamingReplyStatusView(
                    title: isStreamingPaused ? "Pause" : "Replying",
                    animatesTrack: suspendStreamingRender == false,
                    isPaused: isStreamingPaused
                )
            }

            HStack(spacing: 6) {
                Text(message.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.68))

                if message.status == .streaming {
                    Image(systemName: "waveform.and.magnifyingglass")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.68))
                } else if message.status == .failed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }

                #if os(watchOS)
                if canPinMessage {
                    Spacer(minLength: 0)

                    Button {
                        isShowingMessageActions = true
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.52))
                            .frame(width: 28, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                #endif
            }
        }
        .padding(12)
        .background {
            bubbleShape.fill(bubbleBackground)
        }
        .clipShape(bubbleShape)
        .contentShape(bubbleShape)
        .overlay(
            bubbleShape
                .stroke(isUser ? DS.Bubble.userStroke : DS.Bubble.assistantStroke, lineWidth: 1)
        )
        .accessibilityIdentifier("message.bubble.\(message.id.uuidString)")
        #if os(watchOS)
        .confirmationDialog(
            "Message Actions",
            isPresented: $isShowingMessageActions,
            titleVisibility: .visible
        ) {
            messageActions
        } message: {
            Text("Choose how this message should be remembered.")
        }
        #else
        .contextMenu {
            messageActions
        }
        #endif
    }

    private func syncRenderedContentIfNeeded() {
        guard allowsLiveStreamingRender else {
            return
        }

        syncRenderedContent()
    }

    private func syncRenderedContent() {
        renderedText = message.cleanedText
        renderedThoughtSummary = message.cleanedThoughtSummary
    }

    @ViewBuilder
    private var messageTextContent: some View {
        if isUser == false, message.status != .streaming {
            let compactRenderingMode = displayedText.preferredAssistantMessageTextRenderingMode
            let expandedRenderingMode = AssistantMessageTextRenderingDecider.expandedMode(for: displayedText)
            switch (compactRenderingMode, expandedRenderingMode) {
            case (.markdown, _):
                AssistantMessageMarkdownView(text: displayedText)
            case (.plain, .markdown):
                CollapsibleAssistantMessageMarkdownView(
                    text: displayedText,
                    forceExpanded: forceExpandedContent,
                    accessibilityIdentifier: messageBodyAccessibilityIdentifier,
                    expandButtonAccessibilityIdentifier: messageExpandButtonAccessibilityIdentifier
                )
            case (.plain, .plain):
                MessageBodyTextView(
                    text: displayedText,
                    forceExpanded: forceExpandedContent,
                    accessibilityIdentifier: messageBodyAccessibilityIdentifier,
                    expandButtonAccessibilityIdentifier: messageExpandButtonAccessibilityIdentifier
                )
            }
        } else {
            MessageBodyTextView(
                text: displayedText,
                forceExpanded: forceExpandedContent,
                accessibilityIdentifier: messageBodyAccessibilityIdentifier,
                expandButtonAccessibilityIdentifier: messageExpandButtonAccessibilityIdentifier
            )
        }
    }

    @ViewBuilder
    private var messageActions: some View {
        if canPinMessage, let onPinMessage {
            Button("Pin to This Chat") {
                Task {
                    await onPinMessage(message.id, conversationID, .conversation)
                }
            }

            Button("Pin Globally") {
                Task {
                    await onPinMessage(message.id, conversationID, .global)
                }
            }
        }

        Button("Cancel", role: .cancel) {}
    }

    private func resetStreamingHaptics() {
        didTriggerStreamingStartHaptics = false
        didTriggerStreamingBodyHaptics = false
        didTriggerReplyCompletionHaptic = false
        cancelReplyHaptics()
    }

    private func triggerStreamingStartHapticsIfNeeded() {
        guard didTriggerStreamingStartHaptics == false else {
            return
        }

        didTriggerStreamingStartHaptics = true
        startReplyHaptics()
    }

    private func triggerStreamingBodyHapticsIfNeeded() {
        guard didTriggerStreamingBodyHaptics == false else {
            return
        }

        didTriggerStreamingBodyHaptics = true
        extendReplyHapticsForVisibleText()
    }

    private func triggerReplyCompletionHapticIfNeeded() {
        guard didTriggerReplyCompletionHaptic == false else {
            return
        }

        didTriggerReplyCompletionHaptic = true

        #if os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #endif
    }

    private func handleAssistantStatusChange(_ status: ChatMessageStatus) {
        guard isUser == false else {
            return
        }

        guard status != .streaming else {
            return
        }

        cancelReplyHaptics()

        guard status == .sent,
              message.cleanedText.isEmpty == false || message.cleanedThoughtSummary != nil
        else {
            return
        }

        triggerReplyCompletionHapticIfNeeded()
    }

    private func startReplyHaptics() {
        #if os(watchOS)
        cancelReplyHaptics()
        replyHapticTask = Task {
            let device = WKInterfaceDevice.current()
            device.play(.success)
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard Task.isCancelled == false else {
                return
            }

            device.play(.click)
        }
        #endif
    }

    private func extendReplyHapticsForVisibleText() {
        #if os(watchOS)
        cancelReplyHaptics()
        replyHapticTask = Task {
            let device = WKInterfaceDevice.current()
            let intervalNanoseconds: UInt64 = 750_000_000

            device.play(.click)

            for _ in 0..<4 {
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
                guard Task.isCancelled == false else {
                    return
                }

                device.play(.click)
            }
        }
        #endif
    }

    private func cancelReplyHaptics() {
        #if os(watchOS)
        replyHapticTask?.cancel()
        replyHapticTask = nil
        #endif
    }

    private var bubbleBackground: AnyShapeStyle {
        // Both user + assistant now source from the central design system
        // so one place controls the app's chat material language. The
        // assistant gradient replaces a flat `black.opacity(0.38)` fill
        // that read as dead space against watchOS black — a faint
        // vertical gradient adds depth without fighting the text.
        if isUser {
            return AnyShapeStyle(DS.Bubble.userFill)
        }
        return AnyShapeStyle(DS.Bubble.assistantFill)
    }
}

private struct MessageAnchorMarker: View {
    let anchorID: String
    let accessibilityIdentifier: String

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 1)
            .id(anchorID)
            .accessibilityElement()
            .accessibilityIdentifier(accessibilityIdentifier)
            .accessibilityLabel(accessibilityIdentifier)
    }
}

private struct ThoughtSummaryCard: View {
    let thoughtSummary: String
    let isStreaming: Bool
    let toggleAccessibilityIdentifier: String
    let stateAccessibilityIdentifier: String
    @State private var isExpanded = false

    private var normalizedSummary: String {
        thoughtSummary.collapseWhitespace()
    }

    private var expansionStateAccessibilityValue: String {
        isExpanded ? "expanded" : "collapsed"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isStreaming ? "brain.head.profile" : "sparkles.rectangle.stack")
                        .font(.caption2)
                        .foregroundStyle(.cyan.opacity(0.9))

                    Text(isStreaming ? "Thinking" : "Summary")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.88))

                    Spacer(minLength: 0)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.66))
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(toggleAccessibilityIdentifier)
            .accessibilityValue(expansionStateAccessibilityValue)

            Text(normalizedSummary)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.76))
                .multilineTextAlignment(.leading)
                .lineLimit(isExpanded ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier(stateAccessibilityIdentifier)
                .accessibilityLabel("thought-summary-state")
                .accessibilityValue(expansionStateAccessibilityValue)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private enum MessageBodyLayout {
    static let collapsedLineLimit = 12
    static let collapseCharacterThreshold = 1_400
    static let collapseLineThreshold = 14
}

private extension String {
    var shouldCollapseMessageBody: Bool {
        let newlineCount = reduce(into: 0) { count, character in
            if character == "\n" {
                count += 1
            }
        }

        return count > MessageBodyLayout.collapseCharacterThreshold ||
            newlineCount >= MessageBodyLayout.collapseLineThreshold
    }
}

private struct MessageBodyTextView: View {
    let text: String
    let forceExpanded: Bool
    let accessibilityIdentifier: String
    let expandButtonAccessibilityIdentifier: String

    @State private var isExpanded = false

    private var shouldCollapse: Bool {
        forceExpanded == false && text.shouldCollapseMessageBody
    }

    private var expansionStateAccessibilityValue: String {
        if forceExpanded {
            return "forced-expanded"
        }

        guard text.shouldCollapseMessageBody else {
            return "full"
        }

        return isExpanded ? "expanded" : "collapsed"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: shouldCollapse ? 8 : 0) {
            Text(text)
                .font(.body)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(shouldCollapse && isExpanded == false ? MessageBodyLayout.collapsedLineLimit : nil)
                .fixedSize(horizontal: false, vertical: true)

            if shouldCollapse {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Label(isExpanded ? "收起全文" : "展开全文", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.cyan.opacity(0.92))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(expandButtonAccessibilityIdentifier)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityValue(expansionStateAccessibilityValue)
    }
}

private struct CollapsibleAssistantMessageMarkdownView: View {
    let text: String
    let forceExpanded: Bool
    let accessibilityIdentifier: String
    let expandButtonAccessibilityIdentifier: String

    @State private var isExpanded = false

    private var shouldCollapse: Bool {
        forceExpanded == false && text.shouldCollapseMessageBody
    }

    private var expansionStateAccessibilityValue: String {
        if forceExpanded {
            return "forced-expanded"
        }

        guard text.shouldCollapseMessageBody else {
            return "full"
        }

        return isExpanded ? "expanded" : "collapsed"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: shouldCollapse ? 8 : 0) {
            if shouldCollapse, isExpanded == false {
                Text(text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(MessageBodyLayout.collapsedLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .task(id: text) {
                        await AssistantMessageMarkdownView.prewarmIfNeeded(for: text)
                    }
            } else {
                AssistantMessageMarkdownView(text: text)
            }

            if shouldCollapse {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Label(isExpanded ? "收起全文" : "展开全文", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.cyan.opacity(0.92))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(expandButtonAccessibilityIdentifier)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityValue(expansionStateAccessibilityValue)
    }
}

/// Scoped streaming render body for the assistant bubble.
///
/// Observes `StreamingTextPacer` directly so that per-token reveals only
/// invalidate this small subtree — the enclosing `ChatBubbleView` does not
/// subscribe. This is the counterpart to the removed 120ms flush throttle:
/// visible text now arrives frame-by-frame at ~30Hz from the pacer rather
/// than in 120ms chunks through `@Published conversations`.
///
/// `fallbackText` / `fallbackThoughtSummary` cover the multi-stream case:
/// when the user has two conversations streaming concurrently, the pacer's
/// target is whichever stream began most recently. The other conversation's
/// bubble falls back to `message.text` (updated ≥1 Hz via the streaming
/// checkpoint), so its partial reply never disappears when the user
/// navigates between them.
private struct StreamingAssistantBodyView: View {
    @ObservedObject var pacer: StreamingTextPacer

    let messageID: UUID
    let fallbackText: String
    let fallbackThoughtSummary: String?
    let forceExpandedContent: Bool
    let isLatestReplyAnchorTarget: Bool
    let thoughtSummaryToggleAccessibilityIdentifier: String
    let thoughtSummaryStateAccessibilityIdentifier: String
    let messageBodyAccessibilityIdentifier: String
    let expandButtonAccessibilityIdentifier: String
    let latestReplyStartAnchorID: String
    let latestReplyStartAccessibilityIdentifier: String

    private var isTargetingThisMessage: Bool {
        pacer.targetMessageID == messageID
    }

    private var revealedText: String {
        isTargetingThisMessage ? pacer.revealedText : fallbackText
    }

    private var revealedThoughtSummary: String {
        if isTargetingThisMessage {
            return pacer.revealedThoughtSummary
        }
        return fallbackThoughtSummary ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if revealedThoughtSummary.isEmpty == false {
                ThoughtSummaryCard(
                    thoughtSummary: revealedThoughtSummary,
                    isStreaming: true,
                    toggleAccessibilityIdentifier: thoughtSummaryToggleAccessibilityIdentifier,
                    stateAccessibilityIdentifier: thoughtSummaryStateAccessibilityIdentifier
                )
            }

            if revealedText.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white.opacity(0.8))
                    Text(revealedThoughtSummary.isEmpty ? "Thinking" : "Replying")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                }
            } else {
                if isLatestReplyAnchorTarget {
                    MessageAnchorMarker(
                        anchorID: latestReplyStartAnchorID,
                        accessibilityIdentifier: latestReplyStartAccessibilityIdentifier
                    )
                }

                MessageBodyTextView(
                    text: revealedText,
                    forceExpanded: forceExpandedContent,
                    accessibilityIdentifier: messageBodyAccessibilityIdentifier,
                    expandButtonAccessibilityIdentifier: expandButtonAccessibilityIdentifier
                )
            }
        }
    }
}

private struct StreamingReplyStatusView: View {
    let title: String
    let animatesTrack: Bool
    let isPaused: Bool

    private let trackHeight: CGFloat = 5

    private var statusTint: Color {
        isPaused ? Color.gray.opacity(0.88) : Color.cyan.opacity(0.92)
    }

    private var highlightTint: Color {
        isPaused ? Color.white.opacity(0.82) : Color.white.opacity(0.95)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusTint)
                    .frame(width: 6, height: 6)

                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.84))
            }

            GeometryReader { proxy in
                let trackWidth = max(proxy.size.width, 1)
                let leadingCoreWidth = max(trackWidth * 0.22, 18)
                let trailingCoreWidth = max(trackWidth * 0.12, 12)

                if animatesTrack {
                    StreamingTrackAnimator(
                        trackWidth: trackWidth,
                        leadingCoreWidth: leadingCoreWidth,
                        trailingCoreWidth: trailingCoreWidth,
                        statusTint: statusTint,
                        highlightTint: highlightTint,
                        trackHeight: trackHeight
                    )
                } else {
                    statusTrack(
                        trackWidth: trackWidth,
                        leadingCoreWidth: leadingCoreWidth,
                        trailingCoreWidth: trailingCoreWidth,
                        leadingOffset: trackWidth * 0.32,
                        trailingOffset: trackWidth * 0.18,
                        glowOpacity: 0.7
                    )
                }
            }
            .frame(height: trackHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private func statusTrack(
        trackWidth: CGFloat,
        leadingCoreWidth: CGFloat,
        trailingCoreWidth: CGFloat,
        leadingOffset: CGFloat,
        trailingOffset: CGFloat,
        glowOpacity: Double
    ) -> some View {
        let glowWidth = min(trackWidth * 0.56, 72)

        return ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.05),
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.06)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            statusTint.opacity(0.08),
                            statusTint.opacity(0.42),
                            highlightTint.opacity(0.90),
                            statusTint.opacity(0.26),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: glowWidth)
                .offset(x: leadingOffset - glowWidth * 0.24)
                .opacity(glowOpacity)
                #if os(watchOS)
                .opacity(0.7)
                #else
                .blur(radius: 7)
                #endif

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            statusTint.opacity(0.14),
                            statusTint.opacity(0.65),
                            highlightTint.opacity(0.95)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: leadingCoreWidth)
                .offset(x: leadingOffset)
                .shadow(color: statusTint.opacity(0.28), radius: 8, y: 0)

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            statusTint.opacity(0.08),
                            statusTint.opacity(0.34),
                            highlightTint.opacity(0.32)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: trailingCoreWidth)
                .offset(x: trailingOffset)
        }
        .clipShape(Capsule(style: .continuous))
    }
}

/// Uses a repeating SwiftUI animation instead of 30fps TimelineView to drive
/// the streaming glow track — cheaper on watchOS where TimelineView + blur
/// consumes significant GPU budget.
private struct StreamingTrackAnimator: View {
    let trackWidth: CGFloat
    let leadingCoreWidth: CGFloat
    let trailingCoreWidth: CGFloat
    let statusTint: Color
    let highlightTint: Color
    let trackHeight: CGFloat

    @State private var phase: CGFloat = 0

    var body: some View {
        let travel = max(trackWidth - leadingCoreWidth, 0)
        let glowOffset = travel * phase
        let glowWidth = min(trackWidth * 0.56, 72)

        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.05),
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.06)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            statusTint.opacity(0.08),
                            statusTint.opacity(0.42),
                            highlightTint.opacity(0.90),
                            statusTint.opacity(0.26),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: glowWidth)
                .offset(x: glowOffset - glowWidth * 0.24)
                .opacity(0.96)
                #if os(watchOS)
                .opacity(0.7)
                #else
                .blur(radius: 7)
                #endif

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            statusTint.opacity(0.14),
                            statusTint.opacity(0.65),
                            highlightTint.opacity(0.95)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: leadingCoreWidth)
                .offset(x: glowOffset)
                .shadow(color: statusTint.opacity(0.28), radius: 8, y: 0)

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            statusTint.opacity(0.08),
                            statusTint.opacity(0.34),
                            highlightTint.opacity(0.32)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: trailingCoreWidth)
                .offset(x: max(glowOffset - trackWidth * 0.18, 0))
        }
        .clipShape(Capsule(style: .continuous))
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.65)
                .repeatForever(autoreverses: true)
            ) {
                phase = 1
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func compatibleOnChange<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        if #available(iOS 17.0, watchOS 10.0, *) {
            onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            onChange(of: value, perform: action)
        }
    }
}

private struct AttachmentGridView: View {
    let attachments: [ChatAttachment]

    @State private var selectedImageAttachment: ChatAttachment?

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        LazyVGrid(columns: attachments.count == 1 ? [GridItem(.flexible())] : columns, spacing: 6) {
            ForEach(attachments) { attachment in
                if attachment.previewImage != nil {
                    Button {
                        selectedImageAttachment = attachment
                    } label: {
                        AttachmentThumbnailView(
                            attachment: attachment,
                            isZoomable: true
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("message.attachment.\(attachment.id.uuidString)")
                    .accessibilityHint("Tap to enlarge")
                } else {
                    AttachmentThumbnailView(
                        attachment: attachment,
                        isZoomable: false
                    )
                    .accessibilityIdentifier("message.attachment.\(attachment.id.uuidString)")
                }
            }
        }
        .sheet(item: $selectedImageAttachment) { attachment in
            if let image = attachment.previewImage {
                AttachmentImageViewer(
                    image: image,
                    title: attachment.filename
                )
            }
        }
        .accessibilityIdentifier("message.attachment-grid")
    }
}

private struct AttachmentThumbnailView: View {
    let attachment: ChatAttachment
    let isZoomable: Bool

    var body: some View {
        ZStack {
            if let image = attachment.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .overlay(alignment: .topTrailing) {
                        if isZoomable {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(.black.opacity(0.45), in: Circle())
                                .padding(6)
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.12, green: 0.18, blue: 0.24),
                                Color(red: 0.03, green: 0.43, blue: 0.51)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: attachment.isAudio ? "waveform" : "photo")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.92))

                    Text(attachment.isAudio ? "Voice note" : "Attachment")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)

                    if let durationText = formattedDuration(for: attachment.durationSeconds) {
                        Text(durationText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.78))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(10)
            }
        }
        .frame(minHeight: 74)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()

    private func formattedDuration(for durationSeconds: Double?) -> String? {
        guard let durationSeconds, durationSeconds > 0 else {
            return nil
        }

        return Self.durationFormatter.string(from: durationSeconds)
    }
}

private struct AttachmentImageViewer: View {
    let image: UIImage
    let title: String

    #if os(watchOS)
    @State private var crownZoomScale = 1.0
    #endif
    @State private var gestureZoomScale: CGFloat = 1
    @State private var accumulatedGestureZoomScale: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(
                            width: fittedImageSize(in: geometry.size).width * currentZoomScale,
                            height: fittedImageSize(in: geometry.size).height * currentZoomScale
                        )
                        .padding(12)
                        .frame(
                            minWidth: geometry.size.width,
                            minHeight: geometry.size.height,
                            alignment: .center
                        )
                }
                .background(Color.black.ignoresSafeArea())
                #if !os(watchOS)
                .gesture(magnificationGesture)
                #endif
                #if os(watchOS)
                .focusable(true)
                .digitalCrownRotation(
                    $crownZoomScale,
                    from: 1,
                    through: 6,
                    by: 0.05,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
                #endif
            }
            .navigationTitle(viewerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reset") {
                        resetZoom()
                    }
                }
            }
        }
        .accessibilityIdentifier("message.attachment-viewer")
    }

    private var currentZoomScale: CGFloat {
        let platformScale: CGFloat
        #if os(watchOS)
        platformScale = CGFloat(crownZoomScale)
        #else
        platformScale = 1
        #endif

        return max(1, min(platformScale * gestureZoomScale, 6))
    }

    private var viewerTitle: String {
        let trimmedTitle = title.trimmed
        return trimmedTitle.isEmpty ? "Image" : trimmedTitle
    }

    #if !os(watchOS)
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                gestureZoomScale = max(1, min(accumulatedGestureZoomScale * value, 6))
            }
            .onEnded { _ in
                accumulatedGestureZoomScale = gestureZoomScale
            }
    }
    #endif

    private func fittedImageSize(in availableSize: CGSize) -> CGSize {
        let maxWidth = max(availableSize.width - 24, 1)
        let maxHeight = max(availableSize.height - 24, 1)
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return CGSize(width: maxWidth, height: maxHeight)
        }

        let widthScale = maxWidth / sourceSize.width
        let heightScale = maxHeight / sourceSize.height
        let scale = min(widthScale, heightScale)

        return CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
    }

    private func resetZoom() {
        #if os(watchOS)
        crownZoomScale = 1
        #endif
        gestureZoomScale = 1
        accumulatedGestureZoomScale = 1
    }
}
