//
//  CompanionSyncBridge.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import Foundation
import WatchConnectivity
import os

nonisolated struct CompanionDeletedConversationTombstone: Codable, Equatable {
    let id: UUID
    let deletedAt: Date
}

nonisolated enum CompanionSyncStatus: Equatable {
    case unavailable
    case notPaired
    case companionMissing
    case idle
    case reachable

    var description: String {
        switch self {
        case .unavailable:
            #if os(watchOS)
            return L10n.tr("sync.unavailable.watch")
            #else
            return L10n.tr("sync.unavailable.iphone")
            #endif
        case .notPaired:
            #if os(watchOS)
            return L10n.tr("sync.not_paired.watch")
            #else
            return L10n.tr("sync.not_paired.iphone")
            #endif
        case .companionMissing:
            #if os(watchOS)
            return L10n.tr("sync.missing_companion.watch")
            #else
            return L10n.tr("sync.missing_companion.iphone")
            #endif
        case .idle:
            #if os(watchOS)
            return L10n.tr("sync.idle.watch")
            #else
            return L10n.tr("sync.idle.iphone")
            #endif
        case .reachable:
            #if os(watchOS)
            return L10n.tr("sync.live.watch")
            #else
            return L10n.tr("sync.live.iphone")
            #endif
        }
    }
}

nonisolated enum CompanionSyncEvent {
    case upsert(ConversationThread)
    case delete(UUID, deletedAt: Date)
    case deletedConversationTombstones([CompanionDeletedConversationTombstone])
    case snapshot([ConversationThread])
    case syncSummary(ConversationSyncSummary)
    case attachmentBlob(CompanionIncomingAttachmentBlob)
    case globalPinnedMemories([PinnedMemoryItem])
    case promptPresets([PromptPreset])
    case activationRequestCode(String)
    case activationCodeImport(code: String, transferID: String?)
    case relayPairingToken(token: String, expiresAt: Date?)
}

nonisolated struct CompanionIncomingAttachmentBlob {
    let conversationID: UUID
    let messageID: UUID
    let attachmentID: UUID
    let blobFilename: String
    let filename: String
    let mimeType: String
    let kind: ChatAttachmentKind
    let pixelWidth: Int?
    let pixelHeight: Int?
    let durationSeconds: Double?
    let temporaryFileURL: URL
}

/// Bridge between the watch app and its iPhone companion (or vice
/// versa) over WatchConnectivity. This class is `@MainActor`-isolated:
/// every mutable field (`currentStatus`, the closure handler slots,
/// the encoder/decoder) is accessed exclusively from the main actor.
/// `WCSessionDelegate` callbacks arrive on WatchConnectivity's private
/// serial queue — those entry points are `nonisolated` and hop to the
/// main actor before touching any state. Without that hop, the
/// previous implementation racily wrote `currentStatus` and torn-read
/// the handler slots (H1 in the watch-services review).
@MainActor
final class CompanionSyncBridge: NSObject, WCSessionDelegate {
    typealias EventHandler = @MainActor (CompanionSyncEvent) -> Void
    typealias StatusHandler = @MainActor (CompanionSyncStatus) -> Void
    typealias SnapshotProvider = @MainActor () -> [ConversationThread]
    typealias AttachmentFileURLProvider = (String) -> URL?
    typealias DeletedConversationTombstonesProvider = @MainActor () -> [CompanionDeletedConversationTombstone]
    typealias GlobalPinnedMemoriesProvider = @MainActor () -> [PinnedMemoryItem]
    typealias PromptPresetsProvider = @MainActor () -> [PromptPreset]
    typealias SyncSummaryProvider = @MainActor () -> ConversationSyncSummary?

    private static let log = Logger(subsystem: "com.aichat.watch", category: "CompanionSync")

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let syncEnabled: Bool
    private var eventHandler: EventHandler?
    private var statusHandler: StatusHandler?
    private var snapshotProvider: SnapshotProvider?
    private var attachmentFileURLProvider: AttachmentFileURLProvider?
    private var deletedConversationTombstonesProvider: DeletedConversationTombstonesProvider?
    private var globalPinnedMemoriesProvider: GlobalPinnedMemoriesProvider?
    private var promptPresetsProvider: PromptPresetsProvider?
    private var syncSummaryProvider: SyncSummaryProvider?
    /// The attachment-transfer dedupe set is touched from both the
    /// MainActor (`pushXxx` paths) and the WC delegate queue
    /// (`session(didFinish:)`). Keep its lock-protected access pattern
    /// rather than forcing a hop in the file-completion callback —
    /// that one piece legitimately wants to stay non-MainActor.
    nonisolated(unsafe) private var queuedAttachmentTransferBlobFilenames: Set<String> = []
    private let attachmentTransferStateLock = NSLock()

    private(set) var currentStatus: CompanionSyncStatus = .unavailable

    init(isEnabled: Bool = true) {
        self.syncEnabled = isEnabled
        super.init()

        guard syncEnabled, WCSession.isSupported() else {
            currentStatus = .unavailable
            return
        }

        let session = WCSession.default
        session.delegate = self
        session.activate()
        refreshStatus(for: session)
    }

    func setEventHandler(_ handler: EventHandler?) {
        eventHandler = handler
    }

    func setStatusHandler(_ handler: StatusHandler?) {
        statusHandler = handler
        let snapshot = currentStatus
        Task { @MainActor in
            handler?(snapshot)
        }
    }

    func setSnapshotProvider(_ provider: SnapshotProvider?) {
        snapshotProvider = provider
    }

    func setAttachmentFileURLProvider(_ provider: AttachmentFileURLProvider?) {
        attachmentFileURLProvider = provider
    }

    func setDeletedConversationTombstonesProvider(_ provider: DeletedConversationTombstonesProvider?) {
        deletedConversationTombstonesProvider = provider
    }

    func setGlobalPinnedMemoriesProvider(_ provider: GlobalPinnedMemoriesProvider?) {
        globalPinnedMemoriesProvider = provider
    }

    func setPromptPresetsProvider(_ provider: PromptPresetsProvider?) {
        promptPresetsProvider = provider
    }

    func setSyncSummaryProvider(_ provider: SyncSummaryProvider?) {
        syncSummaryProvider = provider
    }

    func pushConversation(_ conversation: ConversationThread) {
        guard syncEnabled, WCSession.isSupported() else {
            return
        }

        let sanitizedConversation = sanitizedConversationPayload(from: conversation)
        let session = WCSession.default
        enqueue(typeKey: "conversation_upsert", encodable: sanitizedConversation, on: session)
        enqueueAttachmentTransfers(for: sanitizedConversation, using: session)
    }

    func pushDeletion(conversationID: UUID, deletedAt: Date) {
        guard syncEnabled, WCSession.isSupported() else {
            return
        }

        let payload: [String: Any] = [
            "type": "conversation_delete",
            "conversationID": conversationID.uuidString,
            "deletedAt": deletedAt.timeIntervalSince1970
        ]
        send(payload: payload, on: WCSession.default, typeKey: "conversation_delete")
    }

    func pushGlobalPinnedMemories(_ items: [PinnedMemoryItem]) {
        guard syncEnabled, WCSession.isSupported() else {
            return
        }

        enqueue(typeKey: "global_pinned_memories", encodable: items, on: WCSession.default)
    }

    func pushPromptPresets(_ items: [PromptPreset]) {
        guard syncEnabled, WCSession.isSupported() else {
            return
        }

        enqueue(typeKey: "prompt_presets", encodable: items, on: WCSession.default)
    }

    func pushSyncSummary(_ summary: ConversationSyncSummary) {
        guard syncEnabled, WCSession.isSupported() else {
            return
        }

        enqueue(typeKey: "sync_summary", encodable: summary, on: WCSession.default)
    }

    func requestBootstrapIfPossible() {
        guard syncEnabled, WCSession.isSupported() else {
            return
        }

        let session = WCSession.default
        guard session.isReachable else {
            return
        }

        session.sendMessage(["type": "bootstrap_request"], replyHandler: nil)
    }

    func pushActivationRequestCode(_ requestCode: String) {
        guard syncEnabled, WCSession.isSupported() else {
            return
        }

        let payload: [String: Any] = [
            "type": "activation_request_code",
            "requestCode": requestCode
        ]
        send(payload: payload, on: WCSession.default, typeKey: "activation_request_code")
    }

    func pushActivationCodeImport(_ activationCode: String) {
        guard syncEnabled, WCSession.isSupported() else {
            return
        }

        let payload: [String: Any] = [
            "type": "activation_code_import",
            "code": activationCode,
            "transferID": UUID().uuidString
        ]
        send(payload: payload, on: WCSession.default, typeKey: "activation_code_import")
    }

    func pushRelayPairingToken(_ pairingToken: String, expiresAt: Date) {
        guard syncEnabled, WCSession.isSupported() else {
            return
        }

        let payload: [String: Any] = [
            "type": "relay_pairing_token",
            "pairingToken": pairingToken,
            "expiresAt": expiresAt.timeIntervalSince1970
        ]
        send(payload: payload, on: WCSession.default, typeKey: "relay_pairing_token")
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.refreshStatus(for: session)
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
        Task { @MainActor [weak self] in
            self?.refreshStatus(for: WCSession.default)
        }
    }
    #endif

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.refreshStatus(for: session)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.refreshStatus(for: session)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let captured = userInfo
        Task { @MainActor [weak self] in
            self?.handleIncoming(payload: captured)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let captured = applicationContext
        Task { @MainActor [weak self] in
            self?.handleIncoming(payload: captured)
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // `incomingAttachmentBlob(from:)` is a pure metadata read from
        // the SDK-provided `WCSessionFile`; safe to compute on the WC
        // queue.
        guard let incomingBlob = Self.incomingAttachmentBlob(from: file) else {
            return
        }

        Task { @MainActor [weak self] in
            self?.eventHandler?(.attachmentBlob(incomingBlob))
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let captured = message
        Task { @MainActor [weak self] in
            self?.handleIncoming(payload: captured)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let captured = message
        Task { @MainActor [weak self] in
            self?.handleIncoming(payload: captured)
        }
        replyHandler(["ok": true])
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        guard let blobFilename = (fileTransfer.file.metadata?["blobFilename"] as? String)?.nonEmptyTrimmed else {
            return
        }

        // Lock-protected mutation of the dedupe set — safe to do on
        // the WC queue.
        attachmentTransferStateLock.lock()
        queuedAttachmentTransferBlobFilenames.remove(blobFilename)
        attachmentTransferStateLock.unlock()
    }

    private func refreshStatus(for session: WCSession) {
        let nextStatus: CompanionSyncStatus

        if session.activationState != .activated {
            nextStatus = .notPaired
        } else if counterpartInstalled(for: session) == false {
            nextStatus = .companionMissing
        } else if session.isReachable {
            nextStatus = .reachable
        } else {
            nextStatus = .idle
        }

        currentStatus = nextStatus
        statusHandler?(nextStatus)
    }

    private func handleIncoming(payload: [String: Any]) {
        guard let type = payload["type"] as? String else {
            return
        }

        switch type {
        case "bootstrap_request":
            sendBootstrapSnapshot()
        case "conversation_upsert":
            guard let base64Payload = payload["payload"] as? String,
                  let data = Data(base64Encoded: base64Payload),
                  let conversation = try? decoder.decode(ConversationThread.self, from: data)
            else {
                return
            }

            eventHandler?(.upsert(conversation))
        case "conversation_delete":
            guard let rawID = payload["conversationID"] as? String,
                  let conversationID = UUID(uuidString: rawID)
            else {
                return
            }

            let deletedAt = (payload["deletedAt"] as? TimeInterval)
                .map(Date.init(timeIntervalSince1970:))
                ?? .now

            eventHandler?(.delete(conversationID, deletedAt: deletedAt))
        case "conversation_snapshot":
            guard let base64Payload = payload["payload"] as? String,
                  let data = Data(base64Encoded: base64Payload),
                  let conversations = try? decoder.decode([ConversationThread].self, from: data)
            else {
                return
            }

            eventHandler?(.snapshot(conversations))
        case "sync_summary":
            guard let base64Payload = payload["payload"] as? String,
                  let data = Data(base64Encoded: base64Payload),
                  let summary = try? decoder.decode(ConversationSyncSummary.self, from: data)
            else {
                return
            }

            eventHandler?(.syncSummary(summary))
        case "bootstrap_snapshot":
            let conversations = (payload["conversationsPayload"] as? String)
                .flatMap { Data(base64Encoded: $0) }
                .flatMap { try? decoder.decode([ConversationThread].self, from: $0) }
            let deletedConversationTombstones = (payload["deletedConversationTombstonesPayload"] as? String)
                .flatMap { Data(base64Encoded: $0) }
                .flatMap { try? decoder.decode([CompanionDeletedConversationTombstone].self, from: $0) }
            let globalPinnedMemories = (payload["globalPinnedPayload"] as? String)
                .flatMap { Data(base64Encoded: $0) }
                .flatMap { try? decoder.decode([PinnedMemoryItem].self, from: $0) }
            let promptPresets = (payload["promptPresetsPayload"] as? String)
                .flatMap { Data(base64Encoded: $0) }
                .flatMap { try? decoder.decode([PromptPreset].self, from: $0) }
            let syncSummary = (payload["syncSummaryPayload"] as? String)
                .flatMap { Data(base64Encoded: $0) }
                .flatMap { try? decoder.decode(ConversationSyncSummary.self, from: $0) }

            if let syncSummary {
                eventHandler?(.syncSummary(syncSummary))
            }

            if let deletedConversationTombstones {
                eventHandler?(.deletedConversationTombstones(deletedConversationTombstones))
            }

            if let conversations {
                eventHandler?(.snapshot(conversations))
            }

            if let globalPinnedMemories {
                eventHandler?(.globalPinnedMemories(globalPinnedMemories))
            }

            if let promptPresets {
                eventHandler?(.promptPresets(promptPresets))
            }
        case "global_pinned_memories":
            guard let base64Payload = payload["payload"] as? String,
                  let data = Data(base64Encoded: base64Payload),
                  let items = try? decoder.decode([PinnedMemoryItem].self, from: data)
            else {
                return
            }

            eventHandler?(.globalPinnedMemories(items))
        case "prompt_presets":
            guard let base64Payload = payload["payload"] as? String,
                  let data = Data(base64Encoded: base64Payload),
                  let presets = try? decoder.decode([PromptPreset].self, from: data)
            else {
                return
            }

            eventHandler?(.promptPresets(presets))
        case "activation_request_code":
            guard let requestCode = payload["requestCode"] as? String else {
                return
            }

            eventHandler?(.activationRequestCode(requestCode))
        case "activation_code_import":
            guard let code = payload["code"] as? String else {
                return
            }

            eventHandler?(.activationCodeImport(
                code: code,
                transferID: payload["transferID"] as? String
            ))
        case "relay_pairing_token":
            guard let pairingToken = payload["pairingToken"] as? String else {
                return
            }

            let expiresAt = (payload["expiresAt"] as? TimeInterval)
                .map(Date.init(timeIntervalSince1970:))

            eventHandler?(.relayPairingToken(token: pairingToken, expiresAt: expiresAt))
        default:
            break
        }
    }

    private func sendBootstrapSnapshot() {
        guard syncEnabled, WCSession.isSupported() else {
            return
        }

        let conversations = (snapshotProvider?() ?? []).map(sanitizedConversationPayload(from:))
        let deletedConversationTombstones = deletedConversationTombstonesProvider?() ?? []
        let globalPinnedMemories = globalPinnedMemoriesProvider?() ?? []
        let promptPresets = promptPresetsProvider?() ?? []
        let syncSummary = syncSummaryProvider?()

        guard let conversationsData = encodeOrLog(conversations, typeKey: "bootstrap_snapshot.conversations"),
              let deletedConversationTombstonesData = encodeOrLog(
                  deletedConversationTombstones,
                  typeKey: "bootstrap_snapshot.tombstones"
              ),
              let globalPinnedData = encodeOrLog(globalPinnedMemories, typeKey: "bootstrap_snapshot.pinned"),
              let promptPresetsData = encodeOrLog(promptPresets, typeKey: "bootstrap_snapshot.prompt_presets")
        else {
            return
        }

        let syncSummaryPayload = syncSummary
            .flatMap { encodeOrLog($0, typeKey: "bootstrap_snapshot.sync_summary") }
            .map { $0.base64EncodedString() }

        let session = WCSession.default
        var payload: [String: Any] = [
            "type": "bootstrap_snapshot",
            "conversationsPayload": conversationsData.base64EncodedString(),
            "deletedConversationTombstonesPayload": deletedConversationTombstonesData.base64EncodedString(),
            "globalPinnedPayload": globalPinnedData.base64EncodedString(),
            "promptPresetsPayload": promptPresetsData.base64EncodedString()
        ]
        if let syncSummaryPayload {
            payload["syncSummaryPayload"] = syncSummaryPayload
        }

        do {
            try session.updateApplicationContext(payload)
            enqueueAttachmentTransfers(for: conversations, using: session)
        } catch {
            Self.log.error(
                "Failed to push bootstrap snapshot via updateApplicationContext: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Encodes `value` and chooses ONE WC transport (sendMessage when
    /// reachable, transferUserInfo otherwise) — never both. Centralizes
    /// the encode + transport selection across all `pushXxx` paths
    /// (M5 + M6 in the watch services review).
    private func enqueue(
        typeKey: String,
        encodable value: Encodable,
        on session: WCSession
    ) {
        guard let data = encodeOrLog(value, typeKey: typeKey) else {
            return
        }

        let payload: [String: Any] = [
            "type": typeKey,
            "payload": data.base64EncodedString()
        ]
        send(payload: payload, on: session, typeKey: typeKey)
    }

    /// Sends a pre-built payload dictionary on a single transport.
    /// `sendMessage` when reachable, `transferUserInfo` otherwise. Do
    /// not call both — every payload crossed the wire twice in the
    /// previous implementation.
    private func send(payload: [String: Any], on session: WCSession, typeKey: String) {
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                // Fall back to userInfo on transient send failures so
                // the payload still reaches the counterpart.
                Self.log.debug(
                    "sendMessage failed for \(typeKey, privacy: .public); falling back to transferUserInfo: \(error.localizedDescription, privacy: .public)"
                )
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func encodeOrLog<T: Encodable>(_ value: T, typeKey: String) -> Data? {
        do {
            return try encoder.encode(value)
        } catch {
            Self.log.error(
                "Failed to encode \(typeKey, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private func sanitizedConversationPayload(from conversation: ConversationThread) -> ConversationThread {
        var sanitizedConversation = conversation

        for messageIndex in sanitizedConversation.messages.indices {
            for attachmentIndex in sanitizedConversation.messages[messageIndex].attachments.indices {
                let blobFilename = sanitizedConversation.messages[messageIndex].attachments[attachmentIndex]
                    .blobFilename?
                    .nonEmptyTrimmed
                guard blobFilename != nil else {
                    continue
                }

                sanitizedConversation.messages[messageIndex].attachments[attachmentIndex].data = Data()
            }
        }

        return sanitizedConversation
    }

    private func enqueueAttachmentTransfers(
        for conversation: ConversationThread,
        using session: WCSession
    ) {
        enqueueAttachmentTransfers(for: [conversation], using: session)
    }

    private func enqueueAttachmentTransfers(
        for conversations: [ConversationThread],
        using session: WCSession
    ) {
        for conversation in conversations {
            for message in conversation.messages {
                for attachment in message.attachments {
                    guard let blobFilename = attachment.blobFilename?.nonEmptyTrimmed,
                          markAttachmentTransferQueued(blobFilename),
                          let fileURL = attachmentFileURLProvider?(blobFilename)
                    else {
                        continue
                    }

                    guard FileManager.default.fileExists(atPath: fileURL.path) else {
                        attachmentTransferStateLock.lock()
                        queuedAttachmentTransferBlobFilenames.remove(blobFilename)
                        attachmentTransferStateLock.unlock()
                        continue
                    }

                    let metadata = attachmentTransferMetadata(
                        conversationID: conversation.id,
                        messageID: message.id,
                        attachment: attachment,
                        blobFilename: blobFilename
                    )
                    session.transferFile(fileURL, metadata: metadata as [String: Any])
                }
            }
        }
    }

    private func markAttachmentTransferQueued(_ blobFilename: String) -> Bool {
        attachmentTransferStateLock.lock()
        defer { attachmentTransferStateLock.unlock() }
        return queuedAttachmentTransferBlobFilenames.insert(blobFilename).inserted
    }

    private func attachmentTransferMetadata(
        conversationID: UUID,
        messageID: UUID,
        attachment: ChatAttachment,
        blobFilename: String
    ) -> [String: NSObject] {
        var metadata: [String: NSObject] = [
            "type": "conversation_attachment_blob" as NSString,
            "conversationID": conversationID.uuidString as NSString,
            "messageID": messageID.uuidString as NSString,
            "attachmentID": attachment.id.uuidString as NSString,
            "blobFilename": blobFilename as NSString,
            "filename": attachment.filename as NSString,
            "mimeType": attachment.mimeType as NSString,
            "kind": attachment.kind.rawValue as NSString
        ]

        if let pixelWidth = attachment.pixelWidth {
            metadata["pixelWidth"] = NSNumber(value: pixelWidth)
        }

        if let pixelHeight = attachment.pixelHeight {
            metadata["pixelHeight"] = NSNumber(value: pixelHeight)
        }

        if let durationSeconds = attachment.durationSeconds {
            metadata["durationSeconds"] = NSNumber(value: durationSeconds)
        }

        return metadata
    }

    nonisolated private static func incomingAttachmentBlob(from file: WCSessionFile) -> CompanionIncomingAttachmentBlob? {
        guard let metadata = file.metadata,
              (metadata["type"] as? String) == "conversation_attachment_blob",
              let rawConversationID = metadata["conversationID"] as? String,
              let rawMessageID = metadata["messageID"] as? String,
              let rawAttachmentID = metadata["attachmentID"] as? String,
              let conversationID = UUID(uuidString: rawConversationID),
              let messageID = UUID(uuidString: rawMessageID),
              let attachmentID = UUID(uuidString: rawAttachmentID),
              let blobFilename = (metadata["blobFilename"] as? String)?.nonEmptyTrimmed,
              let filename = metadata["filename"] as? String,
              let mimeType = metadata["mimeType"] as? String,
              let rawKind = metadata["kind"] as? String,
              let kind = ChatAttachmentKind(rawValue: rawKind)
        else {
            return nil
        }

        return CompanionIncomingAttachmentBlob(
            conversationID: conversationID,
            messageID: messageID,
            attachmentID: attachmentID,
            blobFilename: blobFilename,
            filename: filename,
            mimeType: mimeType,
            kind: kind,
            pixelWidth: metadata["pixelWidth"] as? Int,
            pixelHeight: metadata["pixelHeight"] as? Int,
            durationSeconds: metadata["durationSeconds"] as? Double,
            temporaryFileURL: file.fileURL
        )
    }

    private func counterpartInstalled(for session: WCSession) -> Bool {
        #if os(watchOS)
        return session.isCompanionAppInstalled
        #else
        return session.isWatchAppInstalled
        #endif
    }
}
