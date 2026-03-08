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
            return "No phone sync available"
            #else
            return "No watch sync available"
            #endif
        case .notPaired:
            #if os(watchOS)
            return "Watch is not paired"
            #else
            return "Apple Watch is not paired"
            #endif
        case .companionMissing:
            #if os(watchOS)
            return "Companion iPhone app not installed"
            #else
            return "Watch app not installed"
            #endif
        case .idle:
            #if os(watchOS)
            return "iPhone sync ready in background"
            #else
            return "Watch sync ready in background"
            #endif
        case .reachable:
            #if os(watchOS)
            return "iPhone sync live"
            #else
            return "Watch sync live"
            #endif
        }
    }
}

nonisolated enum CompanionSyncEvent {
    case upsert(ConversationThread)
    case delete(UUID)
    case snapshot([ConversationThread])
}

final class CompanionSyncBridge: NSObject, WCSessionDelegate {
    typealias EventHandler = @MainActor (CompanionSyncEvent) -> Void
    typealias StatusHandler = @MainActor (CompanionSyncStatus) -> Void
    typealias SnapshotProvider = @MainActor () -> [ConversationThread]

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var eventHandler: EventHandler?
    private var statusHandler: StatusHandler?
    private var snapshotProvider: SnapshotProvider?

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
            guard let data = try? self.encoder.encode(conversations) else {
                return
            }

            do {
                try WCSession.default.updateApplicationContext(
                    [
                        "type": "conversation_snapshot",
                        "payload": data.base64EncodedString()
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
