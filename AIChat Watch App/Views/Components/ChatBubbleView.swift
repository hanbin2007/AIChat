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

    @State private var isShowingMessageActions = false
    @State private var didTriggerStreamingStartHaptics = false
    @State private var didTriggerStreamingBodyHaptics = false
    @State private var didTriggerReplyCompletionHaptic = false
    #if os(watchOS)
    @State private var replyHapticTask: Task<Void, Never>?
    #endif

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

    private var hasStartedStreamingBodyText: Bool {
        isStreamingAssistant && message.cleanedText.isEmpty == false
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
                triggerStreamingStartHapticsIfNeeded()
            }

            if hasStartedStreamingBodyText {
                triggerStreamingBodyHapticsIfNeeded()
            }
        }
        .compatibleOnChange(of: message.id) { _ in
            resetStreamingHaptics()
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

            if isUser == false, let thoughtSummary = message.cleanedThoughtSummary {
                ThoughtSummaryCard(
                    thoughtSummary: thoughtSummary,
                    isStreaming: message.status == .streaming
                )
            }

            if message.status == .streaming, message.cleanedText.isEmpty {
                Text(message.cleanedThoughtSummary == nil ? "Thinking" : "Replying")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            } else if message.status == .failed, message.cleanedText.isEmpty {
                Text("Stopped")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            } else if message.cleanedText.isEmpty == false {
                Text(message.cleanedText)
                    .font(.body)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isStreamingAssistant {
                StreamingReplyStatusView(
                    title: message.cleanedText.isEmpty ? (message.cleanedThoughtSummary == nil ? "Thinking" : "Replying") : "Live"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.cyan.opacity(0.92))
                    .frame(width: 6, height: 6)

                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.84))
            }

            GeometryReader { proxy in
                TimelineView(.animation) { context in
                    let trackWidth = max(proxy.size.width, 1)
                    let indicatorWidth = max(trackWidth * 0.34, 18)
                    let phase = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 0.9) / 0.9
                    let travel = max(trackWidth - indicatorWidth, 0)

                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.10))

                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.cyan.opacity(0.28),
                                        Color.cyan.opacity(0.94),
                                        Color.white.opacity(0.92)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: indicatorWidth)
                            .offset(x: travel * phase)
                    }
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
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
