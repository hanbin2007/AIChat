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
            return "No phone sync available"
        case .notPaired:
            return "Watch is not paired"
        case .companionMissing:
            return "Companion iPhone app not installed"
        case .idle:
            return "iPhone sync ready in background"
        case .reachable:
            return "iPhone sync live"
        }
    }
}

nonisolated enum CompanionSyncEvent {
    case upsert(ConversationThread)
    case delete(UUID)
}

final class CompanionSyncBridge: NSObject, WCSessionDelegate {
    typealias EventHandler = @MainActor (CompanionSyncEvent) -> Void
    typealias StatusHandler = @MainActor (CompanionSyncStatus) -> Void

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var eventHandler: EventHandler?
    private var statusHandler: StatusHandler?

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

    private func refreshStatus(for session: WCSession) {
        let nextStatus: CompanionSyncStatus

        if session.activationState != .activated {
            nextStatus = .notPaired
        } else if session.isCompanionAppInstalled == false {
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
        default:
            break
        }
    }
}
