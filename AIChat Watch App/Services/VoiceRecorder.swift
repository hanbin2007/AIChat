//
//  VoiceRecorder.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/8.
//

import AVFoundation
import Combine
import Foundation

enum VoiceRecorderError: LocalizedError {
    case microphoneDenied
    case cannotStart
    case missingRecording

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return L10n.tr("error.voice.microphone_denied")
        case .cannotStart:
            return L10n.tr("error.voice.cannot_start")
        case .missingRecording:
            return L10n.tr("error.voice.missing_recording")
        }
    }
}

@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    private struct RecordingFormat {
        let fileExtension: String
        let mimeType: String
        let settings: [String: Any]
    }

    enum State: Equatable {
        case idle
        case preparing
        case recording
        case finalizing
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var completedAttachment: ChatAttachment?
    @Published private(set) var errorMessage: String?
    @Published private(set) var noticeMessage: String?

    private let audioSession = AVAudioSession.sharedInstance()
    private let maxDuration: TimeInterval = 60
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var recordingFormat: RecordingFormat?
    private var timer: Timer?
    private var capturedDuration: TimeInterval = 0

    var isPreparing: Bool {
        state == .preparing || state == .finalizing
    }

    var isRecording: Bool {
        state == .recording
    }

    var isInteractive: Bool {
        state == .idle
    }

    var elapsedTimeText: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: elapsedTime) ?? "00:00"
    }

    func startRecording() async {
        guard state == .idle else {
            return
        }

        clearError()
        clearNotice()
        completedAttachment = nil
        state = .preparing

        guard await requestPermission() else {
            state = .idle
            errorMessage = VoiceRecorderError.microphoneDenied.localizedDescription
            return
        }

        do {
            try audioSession.setCategory(.record, mode: .default)
            try audioSession.setActive(true)

            let preparedRecording = try makeRecorder()
            let recorder = preparedRecording.recorder

            self.recorder = recorder
            self.recordingURL = preparedRecording.url
            self.recordingFormat = preparedRecording.format
            self.capturedDuration = 0
            self.elapsedTime = 0
            if preparedRecording.format.fileExtension != Self.preferredRecordingFormats.first?.fileExtension {
                noticeMessage = L10n.tr("notice.voice.wav_fallback")
            }
            startTimer()
            state = .recording

            guard recorder.record(forDuration: maxDuration) else {
                throw VoiceRecorderError.cannotStart
            }
        } catch {
            cleanup(shouldRemoveRecording: true)
            errorMessage = error.localizedDescription
            state = .idle
        }
    }

    func stopRecording() {
        guard state == .recording else {
            return
        }

        capturedDuration = recorder?.currentTime ?? elapsedTime
        state = .finalizing
        stopTimer()
        recorder?.stop()
    }

    func clearError() {
        errorMessage = nil
    }

    func clearNotice() {
        noticeMessage = nil
    }

    func consumeCompletedAttachment() {
        completedAttachment = nil
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateElapsedTime()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, watchOS 10.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                audioSession.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func cleanup(shouldRemoveRecording: Bool) {
        stopTimer()
        recorder = nil
        try? audioSession.setActive(false)

        if shouldRemoveRecording, let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }

        recordingURL = nil
        recordingFormat = nil
        capturedDuration = 0
        elapsedTime = 0
    }

    private func updateElapsedTime() {
        elapsedTime = min(recorder?.currentTime ?? elapsedTime, maxDuration)
    }

    private func makeRecorder() throws -> (recorder: AVAudioRecorder, url: URL, format: RecordingFormat) {
        var lastError: Error = VoiceRecorderError.cannotStart

        for format in Self.preferredRecordingFormats {
            let url = makeRecordingURL(withExtension: format.fileExtension)

            do {
                let recorder = try AVAudioRecorder(url: url, settings: format.settings)
                recorder.delegate = self
                recorder.isMeteringEnabled = false

                guard recorder.prepareToRecord() else {
                    throw VoiceRecorderError.cannotStart
                }

                return (recorder, url, format)
            } catch {
                lastError = error
                try? FileManager.default.removeItem(at: url)
            }
        }

        throw lastError
    }

    private func makeRecordingURL(withExtension fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
    }

    private static let preferredRecordingFormats: [RecordingFormat] = [
        RecordingFormat(
            fileExtension: "aac",
            mimeType: "audio/aac",
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 24_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 48_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
        ),
        RecordingFormat(
            fileExtension: "wav",
            mimeType: "audio/wav",
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false
            ]
        )
    ]

    private static func fallbackRecordingFormat(forFileExtension fileExtension: String) -> RecordingFormat {
        preferredRecordingFormats.first(where: { $0.fileExtension == fileExtension.lowercased() }) ??
            preferredRecordingFormats.last!
    }

    private func handleRecordingFinished(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard flag else {
            errorMessage = VoiceRecorderError.cannotStart.localizedDescription
            state = .idle
            cleanup(shouldRemoveRecording: true)
            return
        }

        guard let recordingURL else {
            errorMessage = VoiceRecorderError.missingRecording.localizedDescription
            state = .idle
            cleanup(shouldRemoveRecording: true)
            return
        }

        let format = recordingFormat ?? Self.fallbackRecordingFormat(forFileExtension: recordingURL.pathExtension)
        let durationSeconds = max(capturedDuration, recorder.currentTime, elapsedTime)

        Task {
            defer {
                state = .idle
                cleanup(shouldRemoveRecording: true)
            }

            do {
                completedAttachment = try await Self.makeCompletedAttachment(
                    from: recordingURL,
                    suggestedFilename: recordingURL.lastPathComponent,
                    durationSeconds: durationSeconds,
                    mimeType: format.mimeType
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func makeCompletedAttachment(
        from recordingURL: URL,
        suggestedFilename: String,
        durationSeconds: Double,
        mimeType: String
    ) async throws -> ChatAttachment {
        try await Task.detached(priority: .userInitiated) {
            let rawData = try Data(contentsOf: recordingURL)
            return try ChatAttachment.makeRecordedAudio(
                from: rawData,
                suggestedFilename: suggestedFilename,
                durationSeconds: durationSeconds,
                mimeType: mimeType
            )
        }.value
    }
}

extension VoiceRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            handleRecordingFinished(recorder, successfully: flag)
        }
    }
}
