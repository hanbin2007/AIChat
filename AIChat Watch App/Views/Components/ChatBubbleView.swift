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

struct ChatBubbleView: View, Equatable {
    @EnvironmentObject private var chatStore: ChatStore

    let conversationID: UUID
    let message: ChatMessage
    let suspendStreamingRender: Bool

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

    static func == (lhs: ChatBubbleView, rhs: ChatBubbleView) -> Bool {
        lhs.conversationID == rhs.conversationID &&
        lhs.message.renderSignature == rhs.message.renderSignature &&
        lhs.suspendStreamingRender == rhs.suspendStreamingRender
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
                messageTextContent
            }

            if isStreamingAssistant {
                StreamingReplyStatusView(
                    title: isStreamingPaused ? "Pause" : (displayedText.isEmpty ? (displayedThoughtSummary == nil ? "Thinking" : "Replying") : "Live"),
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
    private var messageTextContent: some View {
        if isUser == false, message.status != .streaming {
            #if os(watchOS)
            switch displayedText.preferredAssistantMessageTextRenderingMode {
            case .plain:
                MessageBodyTextView(text: displayedText)
            case .markdown:
                AssistantMessageMarkdownView(text: displayedText)
            }
            #else
            AssistantMessageMarkdownView(text: displayedText)
            #endif
        } else {
            MessageBodyTextView(text: displayedText)
        }
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

private enum MessageBodyLayout {
    static let collapsedLineLimit = 12
    static let collapseCharacterThreshold = 1_400
    static let collapseLineThreshold = 14
}

private struct MessageBodyTextView: View {
    let text: String

    @State private var isExpanded = false

    private var shouldCollapse: Bool {
        let newlineCount = text.reduce(into: 0) { count, character in
            if character == "\n" {
                count += 1
            }
        }

        return text.count > MessageBodyLayout.collapseCharacterThreshold ||
            newlineCount >= MessageBodyLayout.collapseLineThreshold
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
                .blur(radius: 7)

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
                    .accessibilityHint("Tap to enlarge")
                } else {
                    AttachmentThumbnailView(
                        attachment: attachment,
                        isZoomable: false
                    )
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
