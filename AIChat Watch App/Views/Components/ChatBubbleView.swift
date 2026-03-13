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

struct ChatBubbleView: View {
    @EnvironmentObject private var chatStore: ChatStore

    let conversationID: UUID
    let message: ChatMessage
    let suspendStreamingRender: Bool

    @State private var isShowingMessageActions = false
    @State private var didTriggerStreamingHaptics = false
    @State private var renderedText: String
    @State private var renderedThoughtSummary: String?
    #if os(watchOS)
    @State private var replyHapticTask: Task<Void, Never>?
    #endif

    init(
        conversationID: UUID,
        message: ChatMessage,
        suspendStreamingRender: Bool = false
    ) {
        self.conversationID = conversationID
        self.message = message
        self.suspendStreamingRender = suspendStreamingRender
        _renderedText = State(initialValue: message.cleanedText)
        _renderedThoughtSummary = State(initialValue: message.cleanedThoughtSummary)
    }

    private var isUser: Bool {
        message.role == .user
    }

    private var isStreamingAssistant: Bool {
        isUser == false && message.status == .streaming
    }

    private var hasReceivedStreamingChunk: Bool {
        isStreamingAssistant &&
        (message.cleanedText.isEmpty == false || message.cleanedThoughtSummary != nil)
    }

    private var displayedText: String {
        renderedText
    }

    private var displayedThoughtSummary: String? {
        renderedThoughtSummary
    }

    private var allowsLiveStreamingRender: Bool {
        suspendStreamingRender == false || message.status != .streaming
    }

    private var canPinMessage: Bool {
        message.cleanedText.isEmpty == false
    }

    private var bubbleShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
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
                triggerStreamingHapticsIfNeeded()
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

            triggerStreamingHapticsIfNeeded()
        }
        .compatibleOnChange(of: isStreamingAssistant) { isStreaming in
            guard isStreaming == false else {
                return
            }

            cancelReplyHaptics()
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

            if isUser == false, let thoughtSummary = displayedThoughtSummary {
                ThoughtSummaryCard(
                    thoughtSummary: thoughtSummary,
                    isStreaming: message.status == .streaming
                )
            }

            if message.status == .streaming, displayedText.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white.opacity(0.8))
                    Text(displayedThoughtSummary == nil ? "Thinking" : "Replying")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                }
            } else if message.status == .failed, displayedText.isEmpty {
                Text("Stopped")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            } else if displayedText.isEmpty == false {
                Text(displayedText)
                    .font(.body)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isStreamingAssistant {
                StreamingReplyStatusView(
                    title: displayedText.isEmpty ? (displayedThoughtSummary == nil ? "Thinking" : "Replying") : "Live",
                    showsSpinner: displayedText.isEmpty,
                    animatesTrack: suspendStreamingRender == false
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
                .stroke(Color.white.opacity(isUser ? 0.16 : 0.08), lineWidth: 1)
        )
        #if os(watchOS)
        .onLongPressGesture(minimumDuration: 0.35) {
            guard canPinMessage else {
                return
            }

            isShowingMessageActions = true
        }
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
    private var messageActions: some View {
        if canPinMessage {
            Button("Pin to This Chat") {
                Task {
                    await chatStore.pinMessage(
                        id: message.id,
                        from: conversationID,
                        scope: .conversation
                    )
                }
            }

            Button("Pin Globally") {
                Task {
                    await chatStore.pinMessage(
                        id: message.id,
                        from: conversationID,
                        scope: .global
                    )
                }
            }
        }

        Button("Cancel", role: .cancel) {}
    }

    private func resetStreamingHaptics() {
        didTriggerStreamingHaptics = false
        cancelReplyHaptics()
    }

    private func triggerStreamingHapticsIfNeeded() {
        guard didTriggerStreamingHaptics == false else {
            return
        }

        didTriggerStreamingHaptics = true
        startReplyHaptics()
    }

    private func startReplyHaptics() {
        #if os(watchOS)
        cancelReplyHaptics()
        replyHapticTask = Task {
            let device = WKInterfaceDevice.current()
            let pattern: [(WKHapticType, UInt64)] = [
                (.success, 180_000_000),
                (.click, 200_000_000),
                (.click, 250_000_000),
                (.click, 330_000_000)
            ]

            for (index, step) in pattern.enumerated() {
                guard Task.isCancelled == false else {
                    return
                }

                device.play(step.0)

                if index < pattern.count - 1 {
                    try? await Task.sleep(nanoseconds: step.1)
                }
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
        if isUser {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.0, green: 0.56, blue: 0.70),
                        Color(red: 0.0, green: 0.39, blue: 0.56)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(Color.black.opacity(0.38))
    }
}

private struct ThoughtSummaryCard: View {
    let thoughtSummary: String
    let isStreaming: Bool
    @State private var isExpanded = false

    private var normalizedSummary: String {
        thoughtSummary.collapseWhitespace()
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

            Text(normalizedSummary)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.76))
                .multilineTextAlignment(.leading)
                .lineLimit(isExpanded ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
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

private struct StreamingReplyStatusView: View {
    let title: String
    let showsSpinner: Bool
    let animatesTrack: Bool

    private let trackHeight: CGFloat = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if showsSpinner {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.cyan.opacity(0.92))
                } else {
                    Circle()
                        .fill(Color.cyan.opacity(0.92))
                        .frame(width: 6, height: 6)
                }

                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.84))
            }

            GeometryReader { proxy in
                let trackWidth = max(proxy.size.width, 1)
                let leadingCoreWidth = max(trackWidth * 0.22, 18)
                let trailingCoreWidth = max(trackWidth * 0.12, 12)

                if animatesTrack {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                        let cycle = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 1.65) / 1.65
                        let easedPhase = 0.5 - 0.5 * cos(cycle * .pi * 2)
                        let travel = max(trackWidth - leadingCoreWidth, 0)
                        let glowOffset = travel * easedPhase

                        statusTrack(
                            trackWidth: trackWidth,
                            leadingCoreWidth: leadingCoreWidth,
                            trailingCoreWidth: trailingCoreWidth,
                            leadingOffset: glowOffset,
                            trailingOffset: max(glowOffset - trackWidth * 0.18, 0),
                            glowOpacity: 0.96
                        )
                    }
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
                            Color.cyan.opacity(0.08),
                            Color.cyan.opacity(0.42),
                            Color.white.opacity(0.90),
                            Color.cyan.opacity(0.26),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: glowWidth)
                .offset(x: leadingOffset - glowWidth * 0.24)
                .opacity(glowOpacity)
                .blur(radius: 7)

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.cyan.opacity(0.14),
                            Color.cyan.opacity(0.65),
                            Color.white.opacity(0.95)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: leadingCoreWidth)
                .offset(x: leadingOffset)
                .shadow(color: Color.cyan.opacity(0.28), radius: 8, y: 0)

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.cyan.opacity(0.08),
                            Color.cyan.opacity(0.34),
                            Color.white.opacity(0.32)
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

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        LazyVGrid(columns: attachments.count == 1 ? [GridItem(.flexible())] : columns, spacing: 6) {
            ForEach(attachments) { attachment in
                AttachmentThumbnailView(attachment: attachment)
            }
        }
    }
}

private struct AttachmentThumbnailView: View {
    let attachment: ChatAttachment

    var body: some View {
        ZStack {
            if let image = attachment.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
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

    private func formattedDuration(for durationSeconds: Double?) -> String? {
        guard let durationSeconds, durationSeconds > 0 else {
            return nil
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: durationSeconds)
    }
}
