//
//  VoiceRecordingHelper.swift
//  AIChat Watch App
//
//  Shared voice recording logic used by both ConversationDetailView
//  (watchOS) and CompanionConversationDetailView (iOS).
//

import Foundation

enum VoiceCaptureMode: Equatable {
    case transcribe
    case direct
}

@MainActor
enum VoiceRecordingHelper {

    static func handleVoiceButtonTap(
        voiceRecorder: VoiceRecorder,
        captureMode: VoiceCaptureMode,
        suppressedUntil: Date,
        now: Date = .now
    ) async {
        guard now >= suppressedUntil else { return }
        if voiceRecorder.isRecording {
            voiceRecorder.stopRecording()
        } else {
            await voiceRecorder.startRecording()
        }
    }

    static func handleVoiceButtonLongPress(
        captureMode: inout VoiceCaptureMode,
        suppressedUntil: inout Date,
        voiceRecorder: VoiceRecorder,
        now: Date = .now
    ) {
        suppressedUntil = now.addingTimeInterval(0.5)
        if voiceRecorder.isRecording {
            voiceRecorder.stopRecording()
        }
        captureMode = captureMode == .transcribe ? .direct : .transcribe
    }

    static func toggleVoiceRecording(
        voiceRecorder: VoiceRecorder,
        isRecording: Bool
    ) async {
        if isRecording {
            await voiceRecorder.startRecording()
        } else {
            voiceRecorder.stopRecording()
        }
    }

    static func handleRecordedAttachment(
        attachment: ChatAttachment,
        captureMode: VoiceCaptureMode,
        conversationID: UUID,
        chatStore: ChatStore
    ) async {
        switch captureMode {
        case .transcribe:
            await chatStore.sendRecordedAudio(attachment, in: conversationID)
        case .direct:
            await chatStore.sendRecordedAudioDirectly(attachment, in: conversationID)
        }
    }
}
