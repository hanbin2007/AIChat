//
//  ChatBubbleView.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import SwiftUI

struct ChatBubbleView: View {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: isStreaming ? "brain.head.profile" : "sparkles.rectangle.stack")
                    .font(.caption2)
                    .foregroundStyle(.cyan.opacity(0.9))

                Text(isStreaming ? "Thinking" : "Thought Summary")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
            }

            Text(thoughtSummary)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.76))
                .multilineTextAlignment(.leading)
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
    let attachments: [ChatImageAttachment]

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
    let attachment: ChatImageAttachment

    var body: some View {
        Group {
            if let image = attachment.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(minHeight: 74)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
