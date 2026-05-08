//
//  AttachmentPreview.swift
//  AIChat Watch App
//
//  Compact preview chip for `ChatAttachment`. Images render as a small
//  thumbnail; audio shows a duration chip; unknown kinds fall back to a
//  generic file chip. Designed for inline use inside chat bubbles —
//  width is bounded so it never breaks the bubble layout.
//

import SwiftUI

struct AttachmentPreview: View {
    let attachment: ChatAttachment

    var body: some View {
        switch attachment.kind {
        case .image:
            imageBody
        case .audio:
            audioBody
        }
    }

    private var imageBody: some View {
        Group {
            if let image = attachment.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: 120, maxHeight: 90)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
            } else {
                fallbackChip(symbol: "photo", label: attachment.shortSummary)
            }
        }
    }

    private var audioBody: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "waveform")
                .font(.caption)
            Text(durationLabel)
                .font(DS.Typography.chip)
                .monospacedDigit()
        }
        .padding(.horizontal, DS.Spacing.s)
        .padding(.vertical, DS.Spacing.xs)
        .background(.thinMaterial, in: Capsule())
    }

    private var durationLabel: String {
        guard let seconds = attachment.durationSeconds, seconds > 0 else {
            return attachment.shortSummary
        }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func fallbackChip(symbol: String, label: String) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: symbol).font(.caption)
            Text(label).font(DS.Typography.chip)
        }
        .padding(.horizontal, DS.Spacing.s)
        .padding(.vertical, DS.Spacing.xs)
        .background(.thinMaterial, in: Capsule())
    }
}
