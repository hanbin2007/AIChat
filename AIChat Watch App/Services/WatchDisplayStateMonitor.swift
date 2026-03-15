import Foundation

@MainActor
final class WatchDisplayStateMonitor {
    static let shared = WatchDisplayStateMonitor()

    private(set) var isLuminanceReduced = false

    private init() {}

    func updateLuminanceReduced(_ isLuminanceReduced: Bool) {
        self.isLuminanceReduced = isLuminanceReduced
    }
}
