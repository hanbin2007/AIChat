//
//  CompanionSyncBridge.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import Foundation
import WatchConnectivity

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

final class CompanionSyncBridge: NSObject, WCSessionDelegate {
    typealias EventHandler = @MainActor (CompanionSyncEvent) -> Void
    typealias StatusHandler = @MainActor (CompanionSyncStatus) -> Void
    typealias SnapshotProvider = @MainActor () -> [ConversationThread]
    typealias AttachmentFileURLProvider = (String) -> URL?
    typealias DeletedConversationTombstonesProvider = @MainActor () -> [CompanionDeletedConversationTombstone]
    typealias GlobalPinnedMemoriesProvider = @MainActor () -> [PinnedMemoryItem]
    typealias PromptPresetsProvider = @MainActor () -> [PromptPreset]
    typealias SyncSummaryProvider = @MainActor () -> ConversationSyncSummary?

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
    private var queuedAttachmentTransferBlobFilenames: Set<String> = []
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
        Task { @MainActor in
            handler?(currentStatus)
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

        do {
            let sanitizedConversation = sanitizedConversationPayload(from: conversation)
            let data = try encoder.encode(sanitizedConversation)
            let payload: [String: Any] = [
                "type": "conversation_upsert",
                "payload": data.base64EncodedString()
            ]
            let session = WCSession.default

            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
            }

            session.transferUserInfo(payload)
            enqueueAttachmentTransfers(for: sanitizedConversation, using: session)
        } catch {
            return
        }
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
        let session = WCSession.default

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }

        session.transferUserInfo(payload)
    }

    func pushGlobalPinnedMemories(_ items: [PinnedMemoryItem]) {
        guard syncEnabled, WCSession.isSupported() else {
            return
        }

        do {
            let data = try encoder.encode(items)
            let payload: [String: Any] = [
                "type": "global_pinned_memories",
                "payload": data.base64EncodedString()
            ]
            let session = WCSession.default

            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
            }

            session.transferUserInfo(payload)
        } catch {
            return
        }
    }

    func pushPromptPresets(_ items: [PromptPreset]) {
        guard syncEnabled, WCSession.isSupported() else {
            return
        }

        do {
            let data = try encoder.encode(items)
            let payload: [String: Any] = [
                "type": "prompt_presets",
                "payload": data.base64EncodedString()
            ]
            let session = WCSession.default

            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
            }

            session.transferUserInfo(payload)
        } catch {
            return
        }
    }

    func pushSyncSummary(_ summary: ConversationSyncSummary) {
        guard syncEnabled, WCSession.isSupported() else {
            return
        }

        do {
            let data = try encoder.encode(summary)
            let payload: [String: Any] = [
                "type": "sync_summary",
                "payload": data.base64EncodedString()
            ]
            let session = WCSession.default

            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
            }

            session.transferUserInfo(payload)
        } catch {
            return
        }
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
        let session = WCSession.default

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }

        session.transferUserInfo(payload)
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
        let session = WCSession.default

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }

        session.transferUserInfo(payload)
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
        refreshStatus(for: session)
    }

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
        refreshStatus(for: WCSession.default)
    }
    #endif

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        refreshStatus(for: session)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        refreshStatus(for: session)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handleIncoming(payload: userInfo)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleIncoming(payload: applicationContext)
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let incomingBlob = incomingAttachmentBlob(from: file) else {
            return
        }

        Task { @MainActor in
            eventHandler?(.attachmentBlob(incomingBlob))
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncoming(payload: message)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        handleIncoming(payload: message)
        replyHandler(["ok": true])
    }

    func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        guard let blobFilename = (fileTransfer.file.metadata?["blobFilename"] as? String)?.nonEmptyTrimmed else {
            return
        }

        _ = attachmentTransferStateLock.withLock {
            queuedAttachmentTransferBlobFilenames.remove(blobFilename)
        }
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
        Task { @MainActor in
            statusHandler?(nextStatus)
        }
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

            Task { @MainActor in
                eventHandler?(.upsert(conversation))
            }
        case "conversation_delete":
            guard let rawID = payload["conversationID"] as? String,
                  let conversationID = UUID(uuidString: rawID)
            else {
                return
            }

            let deletedAt = (payload["deletedAt"] as? TimeInterval)
                .map(Date.init(timeIntervalSince1970:))
                ?? .now

            Task { @MainActor in
                eventHandler?(.delete(conversationID, deletedAt: deletedAt))
            }
        case "conversation_snapshot":
            guard let base64Payload = payload["payload"] as? String,
                  let data = Data(base64Encoded: base64Payload),
                  let conversations = try? decoder.decode([ConversationThread].self, from: data)
            else {
                return
            }

            Task { @MainActor in
                eventHandler?(.snapshot(conversations))
            }
        case "sync_summary":
            guard let base64Payload = payload["payload"] as? String,
                  let data = Data(base64Encoded: base64Payload),
                  let summary = try? decoder.decode(ConversationSyncSummary.self, from: data)
            else {
                return
            }

            Task { @MainActor in
                eventHandler?(.syncSummary(summary))
            }
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

            Task { @MainActor in
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
            }
        case "global_pinned_memories":
            guard let base64Payload = payload["payload"] as? String,
                  let data = Data(base64Encoded: base64Payload),
                  let items = try? decoder.decode([PinnedMemoryItem].self, from: data)
            else {
                return
            }

            Task { @MainActor in
                eventHandler?(.globalPinnedMemories(items))
            }
        case "prompt_presets":
            guard let base64Payload = payload["payload"] as? String,
                  let data = Data(base64Encoded: base64Payload),
                  let presets = try? decoder.decode([PromptPreset].self, from: data)
            else {
                return
            }

            Task { @MainActor in
                eventHandler?(.promptPresets(presets))
            }
        case "activation_request_code":
            guard let requestCode = payload["requestCode"] as? String else {
                return
            }

            Task { @MainActor in
                eventHandler?(.activationRequestCode(requestCode))
            }
        case "activation_code_import":
            guard let code = payload["code"] as? String else {
                return
            }

            Task { @MainActor in
                eventHandler?(.activationCodeImport(
                    code: code,
                    transferID: payload["transferID"] as? String
                ))
            }
        default:
            break
        }
    }

    private func sendBootstrapSnapshot() {
        guard syncEnabled, WCSession.isSupported() else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let conversations = (self.snapshotProvider?() ?? []).map(self.sanitizedConversationPayload(from:))
            let deletedConversationTombstones = self.deletedConversationTombstonesProvider?() ?? []
            let globalPinnedMemories = self.globalPinnedMemoriesProvider?() ?? []
            let promptPresets = self.promptPresetsProvider?() ?? []
            let syncSummary = self.syncSummaryProvider?()
            guard let conversationsData = try? self.encoder.encode(conversations),
                  let deletedConversationTombstonesData = try? self.encoder.encode(deletedConversationTombstones),
                  let globalPinnedData = try? self.encoder.encode(globalPinnedMemories),
                  let promptPresetsData = try? self.encoder.encode(promptPresets)
            else {
                return
            }

            let syncSummaryPayload = syncSummary
                .flatMap { try? self.encoder.encode($0) }
                .map { $0.base64EncodedString() }

            do {
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

                try session.updateApplicationContext(payload)
                self.enqueueAttachmentTransfers(for: conversations, using: session)
            } catch {
                return
            }
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
                        _ = attachmentTransferStateLock.withLock {
                            queuedAttachmentTransferBlobFilenames.remove(blobFilename)
                        }
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
        attachmentTransferStateLock.withLock {
            queuedAttachmentTransferBlobFilenames.insert(blobFilename).inserted
        }
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

    private func incomingAttachmentBlob(from file: WCSessionFile) -> CompanionIncomingAttachmentBlob? {
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
