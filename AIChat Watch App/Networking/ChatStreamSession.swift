//
//  ChatStreamSession.swift
//  AIChat Watch App
//
//  Owns one streaming `/v1/chat/stream` request. Default path uses
//  `URLSession.bytes(for:)` so cancellation propagates via Swift
//  Concurrency. The insecure-TLS fallback path uses a
//  `URLSessionDataDelegate` because `bytes(for:)` does not invoke the
//  trust-override delegate.
//

import Foundation

actor ChatStreamSession {
    private let context: RelayRequestContext

    init(context: RelayRequestContext) {
        self.context = context
    }

    /// Stream parsed `RelayChatEvent` values for `request`. The stream
    /// finishes normally on a `done` event and throws via
    /// `RelayClientError` for non-2xx responses, transport errors, or
    /// `error` SSE events. Cancelling the consumer task aborts the
    /// underlying URL request.
    nonisolated func stream(
        request: URLRequest,
        allowsInsecureTLS: Bool,
        allowedHost: String?
    ) -> AsyncThrowingStream<RelayChatEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if allowsInsecureTLS, let host = allowedHost {
                        try await runDelegateStream(
                            request: request,
                            allowedHost: host,
                            continuation: continuation
                        )
                    } else {
                        try await runBytesStream(
                            request: request,
                            continuation: continuation
                        )
                    }
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private nonisolated func runBytesStream(
        request: URLRequest,
        continuation: AsyncThrowingStream<RelayChatEvent, Error>.Continuation
    ) async throws {
        let session = URLSession.shared
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RelayClientError.invalidResponse
        }

        if (200...299).contains(http.statusCode) == false {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > 16_384 { break }
            }
            throw RelayClientError.from(
                status: http.statusCode,
                body: body,
                headers: http.allHeaderFields
            )
        }

        let parser = SSEParser()
        var pending = Data()
        let dispatcher = StreamDispatcher(continuation: continuation)
        for try await byte in bytes {
            pending.append(byte)
            if byte == 0x0A {
                let events = parser.feed(pending)
                pending.removeAll(keepingCapacity: true)
                for event in events {
                    if dispatcher.dispatch(event) == .terminated {
                        return
                    }
                }
            }
        }
        if pending.isEmpty == false {
            let events = parser.feed(pending)
            for event in events {
                if dispatcher.dispatch(event) == .terminated {
                    return
                }
            }
        }
        if let trailing = parser.flush() {
            _ = dispatcher.dispatch(trailing)
        }
        dispatcher.finalizeIfNeeded()
    }

    private nonisolated func runDelegateStream(
        request: URLRequest,
        allowedHost: String,
        continuation: AsyncThrowingStream<RelayChatEvent, Error>.Continuation
    ) async throws {
        let delegate = StreamDelegate(allowedHost: allowedHost, continuation: continuation)
        let session = RelayURLSessionFactory.makeStreamingSession(delegate: delegate)
        let task = session.dataTask(with: request)
        delegate.attach(task: task, session: session)
        await withTaskCancellationHandler {
            await delegate.startAndAwait(task: task)
        } onCancel: {
            delegate.cancel()
        }
    }
}

nonisolated private enum StreamDispatchOutcome { case continued, terminated }

/// Decodes parsed SSE events into `RelayChatEvent` values and yields
/// them on the continuation. Tracks done/error so `finalizeIfNeeded()`
/// can emit `incompleteResponse` when the upstream closed without a
/// terminal event.
nonisolated private final class StreamDispatcher: @unchecked Sendable {
    private let continuation: AsyncThrowingStream<RelayChatEvent, Error>.Continuation
    private var didReceiveDone = false
    private var didFail = false
    private var finalized = false

    init(continuation: AsyncThrowingStream<RelayChatEvent, Error>.Continuation) {
        self.continuation = continuation
    }

    @discardableResult
    func dispatch(_ event: SSEEvent) -> StreamDispatchOutcome {
        guard finalized == false else { return .terminated }
        guard let payloadData = event.data.data(using: .utf8) else {
            return .continued
        }
        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(RelayStreamFrame.self, from: payloadData) else {
            return .continued
        }

        let resolvedType = payload.type?.nonEmptyTrimmed ?? event.event
        switch resolvedType {
        case "answer_delta":
            if let text = payload.text, text.isEmpty == false {
                continuation.yield(.answerDelta(text))
            }
        case "thought_delta":
            if let text = payload.text, text.isEmpty == false {
                continuation.yield(.thoughtDelta(text))
            }
        case "model_content":
            if let parts = payload.parts, parts.isEmpty == false {
                continuation.yield(.modelContent(parts))
            }
        case "attachment":
            if let attachment = payload.attachment {
                continuation.yield(.attachment(attachment))
            }
        case "error":
            didFail = true
            let message = payload.message ?? L10n.tr("error.relay.invalid_response")
            continuation.yield(.errorEvent(message))
            finalize(throwing: RelayClientError.remote(message: message))
            return .terminated
        case "done":
            didReceiveDone = true
            continuation.yield(.done(finishReason: payload.finishReason?.nonEmptyTrimmed))
            finalize(throwing: nil)
            return .terminated
        default:
            // Unknown event names (including the legacy `delta` synonym)
            // are intentionally ignored to keep the wire contract strict.
            break
        }
        return .continued
    }

    func finalizeIfNeeded() {
        guard finalized == false else { return }
        if didReceiveDone || didFail {
            finalize(throwing: nil)
        } else {
            finalize(throwing: RelayClientError.incompleteResponse)
        }
    }

    private func finalize(throwing error: Error?) {
        guard finalized == false else { return }
        finalized = true
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}

/// Delegate-driven streaming used only when self-signed TLS is enabled.
nonisolated private final class StreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let allowedHost: String
    private let continuation: AsyncThrowingStream<RelayChatEvent, Error>.Continuation
    private let parser = SSEParser()
    private let dispatcher: StreamDispatcher
    private weak var task: URLSessionDataTask?
    private weak var session: URLSession?
    private var responseStatus: Int?
    private var errorBody = Data()
    private var completion: CheckedContinuation<Void, Never>?
    private let lock = NSLock()

    init(allowedHost: String, continuation: AsyncThrowingStream<RelayChatEvent, Error>.Continuation) {
        self.allowedHost = allowedHost.lowercased()
        self.continuation = continuation
        self.dispatcher = StreamDispatcher(continuation: continuation)
        super.init()
    }

    func attach(task: URLSessionDataTask, session: URLSession) {
        self.task = task
        self.session = session
    }

    func startAndAwait(task: URLSessionDataTask) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            self.completion = cont
            lock.unlock()
            task.resume()
        }
    }

    func cancel() {
        task?.cancel()
        session?.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.lowercased() == allowedHost,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        responseStatus = (response as? HTTPURLResponse)?.statusCode
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let status = responseStatus, (200...299).contains(status) == false {
            errorBody.append(data)
            return
        }
        let events = parser.feed(data)
        for event in events {
            if dispatcher.dispatch(event) == .terminated {
                cancel()
                return
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { resumeCompletionIfNeeded() }
        if let error {
            continuation.finish(throwing: error)
            return
        }
        if let status = responseStatus, (200...299).contains(status) == false {
            let headers = (task.response as? HTTPURLResponse)?.allHeaderFields ?? [:]
            continuation.finish(throwing: RelayClientError.from(status: status, body: errorBody, headers: headers))
            return
        }
        if let trailing = parser.flush() {
            _ = dispatcher.dispatch(trailing)
        }
        dispatcher.finalizeIfNeeded()
    }

    private func resumeCompletionIfNeeded() {
        lock.lock()
        let waiter = completion
        completion = nil
        lock.unlock()
        waiter?.resume()
    }
}
