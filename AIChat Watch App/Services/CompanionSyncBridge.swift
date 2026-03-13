//
//  CompanionSyncBridge.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import Foundation
import WatchConnectivity

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
    case delete(UUID)
    case snapshot([ConversationThread])
    case globalPinnedMemories([PinnedMemoryItem])
    case promptPresets([PromptPreset])
    case activationRequestCode(String)
    case activationCodeImport(code: String, transferID: String?)
}

final class CompanionSyncBridge: NSObject, WCSessionDelegate {
    typealias EventHandler = @MainActor (CompanionSyncEvent) -> Void
    typealias StatusHandler = @MainActor (CompanionSyncStatus) -> Void
    typealias SnapshotProvider = @MainActor () -> [ConversationThread]
    typealias GlobalPinnedMemoriesProvider = @MainActor () -> [PinnedMemoryItem]
    typealias PromptPresetsProvider = @MainActor () -> [PromptPreset]

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var eventHandler: EventHandler?
    private var statusHandler: StatusHandler?
    private var snapshotProvider: SnapshotProvider?
    private var globalPinnedMemoriesProvider: GlobalPinnedMemoriesProvider?
    private var promptPresetsProvider: PromptPresetsProvider?

    private(set) var currentStatus: CompanionSyncStatus = .unavailable

    override init() {
        super.init()

        guard WCSession.isSupported() else {
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

    func setGlobalPinnedMemoriesProvider(_ provider: GlobalPinnedMemoriesProvider?) {
        globalPinnedMemoriesProvider = provider
    }

    func setPromptPresetsProvider(_ provider: PromptPresetsProvider?) {
        promptPresetsProvider = provider
    }

    func pushConversation(_ conversation: ConversationThread) {
        guard WCSession.isSupported() else {
            return
        }

        do {
            let data = try encoder.encode(conversation)
            WCSession.default.transferUserInfo(
                [
                    "type": "conversation_upsert",
                    "payload": data.base64EncodedString()
                ]
            )
        } catch {
            return
        }
    }

    func pushDeletion(conversationID: UUID) {
        guard WCSession.isSupported() else {
            return
        }

        WCSession.default.transferUserInfo(
            [
                "type": "conversation_delete",
                "conversationID": conversationID.uuidString
            ]
        )
    }

    func pushGlobalPinnedMemories(_ items: [PinnedMemoryItem]) {
        guard WCSession.isSupported() else {
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
        guard WCSession.isSupported() else {
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

    func requestBootstrapIfPossible() {
        guard WCSession.isSupported() else {
            return
        }

        let session = WCSession.default
        guard session.isReachable else {
            return
        }

        session.sendMessage(["type": "bootstrap_request"], replyHandler: nil)
    }

    func pushActivationRequestCode(_ requestCode: String) {
        guard WCSession.isSupported() else {
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
        guard WCSession.isSupported() else {
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

            Task { @MainActor in
                eventHandler?(.delete(conversationID))
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
        case "bootstrap_snapshot":
            if let base64Payload = payload["conversationsPayload"] as? String,
               let data = Data(base64Encoded: base64Payload),
               let conversations = try? decoder.decode([ConversationThread].self, from: data) {
                Task { @MainActor in
                    eventHandler?(.snapshot(conversations))
                }
            }

            if let base64Payload = payload["globalPinnedPayload"] as? String,
               let data = Data(base64Encoded: base64Payload),
               let items = try? decoder.decode([PinnedMemoryItem].self, from: data) {
                Task { @MainActor in
                    eventHandler?(.globalPinnedMemories(items))
                }
            }

            if let base64Payload = payload["promptPresetsPayload"] as? String,
               let data = Data(base64Encoded: base64Payload),
               let presets = try? decoder.decode([PromptPreset].self, from: data) {
                Task { @MainActor in
                    eventHandler?(.promptPresets(presets))
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
        guard WCSession.isSupported() else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let conversations = self.snapshotProvider?() ?? []
            let globalPinnedMemories = self.globalPinnedMemoriesProvider?() ?? []
            let promptPresets = self.promptPresetsProvider?() ?? []
            guard let conversationsData = try? self.encoder.encode(conversations),
                  let globalPinnedData = try? self.encoder.encode(globalPinnedMemories),
                  let promptPresetsData = try? self.encoder.encode(promptPresets)
            else {
                return
            }

            do {
                try WCSession.default.updateApplicationContext(
                    [
                        "type": "bootstrap_snapshot",
                        "conversationsPayload": conversationsData.base64EncodedString(),
                        "globalPinnedPayload": globalPinnedData.base64EncodedString(),
                        "promptPresetsPayload": promptPresetsData.base64EncodedString()
                    ]
                )
            } catch {
                return
            }
        }
    }

    private func counterpartInstalled(for session: WCSession) -> Bool {
        #if os(watchOS)
        return session.isCompanionAppInstalled
        #else
        return session.isWatchAppInstalled
        #endif
    }
}
