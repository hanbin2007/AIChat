import Foundation

enum AIChatDeepLink: Equatable {
    case activationImport(String)
    case newConversation

    init?(_ url: URL) {
        guard url.scheme?.lowercased() == "aichat" else {
            return nil
        }

        switch url.host?.lowercased() {
        case "activation":
            guard let activationCode = Self.activationCode(from: url) else {
                return nil
            }
            self = .activationImport(activationCode)
        case "conversation":
            guard Self.isNewConversationPath(url.path) else {
                return nil
            }
            self = .newConversation
        default:
            return nil
        }
    }

    /// Cap defensive max length on the `?code=` query value so a megabyte URL
    /// can never reach the activation pipeline. Any legitimate activation code
    /// (legacy 35-byte Crockford or compact 46-letter) sits well under this.
    private static let maxActivationCodeQueryLength = 256

    private static func activationCode(from url: URL) -> String? {
        let normalizedPath = url.path.lowercased()
        guard normalizedPath.isEmpty || normalizedPath == "/" || normalizedPath == "/import" else {
            return nil
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            return nil
        }

        guard code.count <= maxActivationCodeQueryLength else {
            return nil
        }

        let normalizedCode = OfflineActivation.normalizeActivationInput(code)
        guard normalizedCode.isEmpty == false else {
            return nil
        }

        if code.contains(where: \.isNumber) {
            return OfflineActivation.formatForDisplay(normalizedCode, groupSize: 4)
        }

        return OfflineActivation.formatActivationCodeForDisplay(normalizedCode)
    }

    private static func isNewConversationPath(_ path: String) -> Bool {
        let normalizedPath = path.lowercased()
        return normalizedPath == "/new" || normalizedPath == "/create"
    }
}
