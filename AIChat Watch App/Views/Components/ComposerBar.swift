//
//  ComposerBar.swift
//  AIChat Watch App
//
//  Bottom-of-detail input row with three affordances:
//    1. Text input (tappable text field that opens the system input UI)
//    2. Microphone button — opens the VoiceRecorderView sheet
//    3. Tools button — opens the ToolMenu sheet
//
//  Owns no async work; calls callbacks back to the parent detail view.
//

import SwiftUI

struct ComposerBar: View {
    @Binding var draft: String
    let canSend: Bool
    let isStreaming: Bool
    let onSend: () -> Void
    let onCancelStream: () -> Void
    let onMicrophone: () -> Void
    let onTools: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            TextField("Compose message", text: $draft, axis: .vertical)
                .lineLimit(1...3)
                .font(DS.Typography.bubbleBody)
                .padding(.horizontal, DS.Spacing.s)
                .padding(.vertical, DS.Spacing.xs)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
                .accessibilityLabel("Compose message")

            if isStreaming {
                Button(action: onCancelStream) {
                    Image(systemName: "stop.fill")
                        .foregroundStyle(DS.Status.danger)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop response")
            } else if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: onMicrophone) {
                    Image(systemName: "mic.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Record voice message")
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }

            Button(action: onTools) {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tools")
        }
        .padding(.horizontal, DS.Spacing.s)
        .padding(.vertical, DS.Spacing.xs)
    }
}
