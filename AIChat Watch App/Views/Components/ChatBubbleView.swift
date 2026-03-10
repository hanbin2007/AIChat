//
//  ChatBubbleView.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import SwiftUI

struct ChatBubbleView: View {
    @EnvironmentObject private var chatStore: ChatStore

    let conversationID: UUID
    let message: ChatMessage

    private var isUser: Bool {
        message.role == .user
    }

    private var bubbleShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if isUser {
                Spacer(minLength: 24)
            }

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
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.white.opacity(0.8))
                        Text(message.cleanedThoughtSummary == nil ? "Thinking..." : "Drafting answer...")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                } else if message.status == .failed, message.cleanedText.isEmpty {
                    Text("Reply interrupted")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                } else if message.cleanedText.isEmpty == false {
                    Text(message.cleanedText)
                        .font(.body)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                }

                HStack(spacing: 6) {
                    Text(message.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.68))

                    if message.status == .streaming {
                        Label("Live", systemImage: "waveform.and.magnifyingglass")
                            .labelStyle(.iconOnly)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.68))
                    } else if message.status == .failed {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
            }
            .padding(10)
            .background {
                bubbleShape.fill(bubbleBackground)
            }
            .clipShape(bubbleShape)
            .overlay(
                bubbleShape
                    .stroke(Color.white.opacity(isUser ? 0.16 : 0.08), lineWidth: 1)
            )
            .contextMenu {
                if message.cleanedText.isEmpty == false {
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
            }

            if isUser == false {
                Spacer(minLength: 24)
            }
        }
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

                    Text(isStreaming ? "Thinking" : "Thought Summary")
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
