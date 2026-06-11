import Foundation

enum RelayError: Error, Equatable {
    case unauthorized
    case decodingFailed(String)
    case transport(String)
    case server(Int)
    case notConfigured
}

protocol RelayClient: Sendable {
    func fetchSnapshot() async throws -> RelaySnapshot
}

struct FakeRelayClient: RelayClient {
    var result: Result<RelaySnapshot, RelayError>
    func fetchSnapshot() async throws -> RelaySnapshot {
        switch result {
        case let .success(s): return s
        case let .failure(e): throw e
        }
    }
}
