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

    private let audioSession = AVAudioSession.sharedInstance()
    private let maxDuration: TimeInterval = 60
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
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

            let recordingURL = makeRecordingURL()
            let recorder = try AVAudioRecorder(url: recordingURL, settings: Self.recordingSettings)
            recorder.delegate = self
            recorder.isMeteringEnabled = false

            guard recorder.prepareToRecord() else {
                throw VoiceRecorderError.cannotStart
            }

            self.recorder = recorder
            self.recordingURL = recordingURL
            self.capturedDuration = 0
            self.elapsedTime = 0
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

    private func makeRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
    }

    private func cleanup(shouldRemoveRecording: Bool) {
        stopTimer()
        recorder = nil
        try? audioSession.setActive(false)

        if shouldRemoveRecording, let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }

        recordingURL = nil
        capturedDuration = 0
        elapsedTime = 0
    }

    private func updateElapsedTime() {
        elapsedTime = min(recorder?.currentTime ?? elapsedTime, maxDuration)
    }

    private static var recordingSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]
    }

    private func handleRecordingFinished(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        defer {
            state = .idle
            cleanup(shouldRemoveRecording: true)
        }

        guard flag else {
            errorMessage = VoiceRecorderError.cannotStart.localizedDescription
            return
        }

        guard let recordingURL else {
            errorMessage = VoiceRecorderError.missingRecording.localizedDescription
            return
        }

        do {
            let rawData = try Data(contentsOf: recordingURL)
            completedAttachment = try ChatAttachment.makeRecordedAudio(
                from: rawData,
                suggestedFilename: recordingURL.lastPathComponent,
                durationSeconds: max(capturedDuration, recorder.currentTime, elapsedTime)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension VoiceRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            handleRecordingFinished(recorder, successfully: flag)
        }
    }
}
