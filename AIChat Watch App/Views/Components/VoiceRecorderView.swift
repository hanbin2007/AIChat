//
//  VoiceRecorderView.swift
//  AIChat Watch App
//
//  Modal sheet driving `VoiceRecorder`. Shows elapsed time, a pulsing
//  microphone, and Cancel / Stop buttons. On stop, the parent detail
//  view receives the `ChatAttachment` and decides whether to:
//    1. attach it directly to the next message, or
//    2. send it through the transcription pipeline first
//
//  Both flows are owned by `ConversationDetailViewModel`; this view is
//  pure UI over `VoiceRecorder`'s @Published state.
//

import SwiftUI

struct VoiceRecorderView: View {
    @StateObject private var recorder = VoiceRecorder()

    let onComplete: (ChatAttachment) -> Void
    let onCancel: () -> Void

    @State private var pulseOn = false

    var body: some View {
        VStack(spacing: DS.Spacing.l) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(recorder.isRecording ? DS.Status.danger.opacity(0.25) : Color.secondary.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .scaleEffect(recorder.isRecording && pulseOn ? 1.15 : 1.0)
                    .animation(
                        recorder.isRecording
                            ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                            : .default,
                        value: pulseOn
                    )
                Image(systemName: recorder.isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(recorder.isRecording ? DS.Status.danger : .primary)
            }
            .accessibilityHidden(true)

            Text(recorder.elapsedTimeText)
                .font(.title2.monospacedDigit())

            if let error = recorder.errorMessage {
                Text(error)
                    .font(DS.Typography.bubbleMeta)
                    .foregroundStyle(DS.Status.danger)
                    .multilineTextAlignment(.center)
            } else if let notice = recorder.noticeMessage {
                Text(notice)
                    .font(DS.Typography.bubbleMeta)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            HStack(spacing: DS.Spacing.m) {
                Button(role: .cancel) {
                    onCancel()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(.bordered)

                Button {
                    recorder.stopRecording()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.Status.danger)
                .disabled(!recorder.isRecording)
            }
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, DS.Spacing.s)
        .task {
            pulseOn = true
            if recorder.isInteractive {
                await recorder.startRecording()
            }
        }
        .onChange(of: recorder.completedAttachment) { _, newValue in
            if let attachment = newValue {
                onComplete(attachment)
            }
        }
    }
}
