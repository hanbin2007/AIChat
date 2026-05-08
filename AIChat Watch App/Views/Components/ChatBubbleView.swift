//
//  ChatBubbleView.swift
//  AIChat Watch App
//
//  Renders a single `ChatMessage` in the conversation detail.
//  Responsibilities:
//    • role-based alignment + materials (user = right, assistant = left)
//    • markdown / math rendering for assistant text via
//      `AssistantMessageMarkdownView`
//    • collapsible thought summary for assistant messages
//    • streaming cursor (▍) on the latest streaming assistant bubble
//    • inline attachments via `AttachmentPreview`
//    • inline retry affordance on `.failed` status
//    • normalization through `AssistantMessageContentNormalizer` so
//      embedded data-URI images become real attachments
//

import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage
    var isLastStreaming: Bool = false
    var onRetry: (() -> Void)?

    @State private var thoughtExpanded = false

    private var normalized: ChatMessage {
        AssistantMessageContentNormalizer.normalized(message: message)
    }

    var body: some View {
        let m = normalized
        HStack {
            if m.role == .user { Spacer(minLength: DS.Spacing.l) }
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                if m.role == .assistant, let thought = m.cleanedThoughtSummary {
                    thoughtSection(thought)
                }
                if !m.cleanedText.isEmpty {
                    textSection(text: m.cleanedText, role: m.role)
                }
                if !m.attachments.isEmpty {
                    attachmentsSection(m.attachments)
                }
                if m.status == .failed {
                    failedFooter
                }
                if isLastStreaming && m.role == .assistant {
                    streamingCursor
                }
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.vertical, DS.Spacing.s)
            .background(bubbleMaterial(for: m.role), in: RoundedRectangle(cornerRadius: DS.Radius.bubble, style: .continuous))
            .frame(maxWidth: .infinity, alignment: m.role == .user ? .trailing : .leading)
            if m.role != .user { Spacer(minLength: DS.Spacing.l) }
        }
    }

    // MARK: - Subviews

    private func textSection(text: String, role: ChatRole) -> some View {
        Group {
            if role == .assistant {
                AssistantMessageMarkdownView(text: text)
            } else {
                Text(text)
                    .font(DS.Typography.bubbleBody)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func thoughtSection(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Button {
                thoughtExpanded.toggle()
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: thoughtExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Text("Thinking")
                        .font(DS.Typography.chip)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            if thoughtExpanded {
                Text(summary)
                    .font(DS.Typography.bubbleMeta)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func attachmentsSection(_ attachments: [ChatAttachment]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            ForEach(attachments) { attachment in
                AttachmentPreview(attachment: attachment)
            }
        }
    }

    private var failedFooter: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(DS.Status.danger)
            Text("Send Failed")
                .font(DS.Typography.bubbleMeta)
                .foregroundStyle(DS.Status.danger)
            Spacer()
            if let onRetry {
                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
    }

    private var streamingCursor: some View {
        Text("▍")
            .font(DS.Typography.bubbleBody)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    private func bubbleMaterial(for role: ChatRole) -> AnyShapeStyle {
        switch role {
        case .user:
            return AnyShapeStyle(.regularMaterial)
        case .assistant, .system:
            return AnyShapeStyle(.thinMaterial)
        }
    }
}
