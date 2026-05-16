import Foundation

/// Mirrors Codex CLI's managed ChatGPT logout behavior: revoke the refresh token
/// when available, fall back to the access token, and let callers delete local
/// auth even if the revoke request fails.
final class OAuthLogout {
    private let clientId = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let defaultRevokeEndpoint = "https://auth.openai.com/oauth/revoke"

    func revoke(authJson: AuthDotJson?) async throws {
        guard let (token, kind) = revocableToken(from: authJson) else { return }
        var request = URLRequest(url: revokeEndpoint())
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: String] = [
            "token": token,
            "token_type_hint": kind.tokenTypeHint
        ]
        if let clientId = kind.clientId(clientId) {
            body["client_id"] = clientId
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OAuthLogoutError.noHTTPResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.errorMessage(from: data) ?? String(data: data, encoding: .utf8) ?? "<empty>"
            throw OAuthLogoutError.revokeFailed(kind: kind.tokenTypeHint, status: http.statusCode, message: message)
        }
    }

    private func revocableToken(from authJson: AuthDotJson?) -> (String, RevokeTokenKind)? {
        guard isManagedChatGPTAuth(authJson), let tokens = authJson?.tokens else { return nil }
        if !tokens.refreshToken.isEmpty {
            return (tokens.refreshToken, .refresh)
        }
        if !tokens.accessToken.isEmpty {
            return (tokens.accessToken, .access)
        }
        return nil
    }

    private func isManagedChatGPTAuth(_ authJson: AuthDotJson?) -> Bool {
        guard let authJson else { return false }
        if let mode = authJson.authMode?.lowercased() {
            return mode == "chatgpt"
        }
        return authJson.openaiApiKey == nil && authJson.tokens != nil
    }

    private func revokeEndpoint() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let override = env["CODEX_REVOKE_TOKEN_URL_OVERRIDE"], let url = URL(string: override) {
            return url
        }
        if let refreshOverride = env["CODEX_REFRESH_TOKEN_URL_OVERRIDE"],
           let derived = Self.deriveRevokeEndpoint(from: refreshOverride) {
            return derived
        }
        return URL(string: defaultRevokeEndpoint)!
    }

    private static func deriveRevokeEndpoint(from refreshEndpoint: String) -> URL? {
        guard var components = URLComponents(string: refreshEndpoint) else { return nil }
        components.path = "/oauth/revoke"
        components.query = nil
        return components.url
    }

    private static func errorMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? [String: Any]
        else {
            return nil
        }
        return error["message"] as? String
    }
}

private enum RevokeTokenKind {
    case access
    case refresh

    var tokenTypeHint: String {
        switch self {
        case .access: return "access_token"
        case .refresh: return "refresh_token"
        }
    }

    func clientId(_ value: String) -> String? {
        switch self {
        case .access: return nil
        case .refresh: return value
        }
    }
}

enum OAuthLogoutError: Error, LocalizedError {
    case noHTTPResponse
    case revokeFailed(kind: String, status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noHTTPResponse:
            return "No HTTP response from OAuth revoke endpoint."
        case .revokeFailed(let kind, let status, let message):
            return "Failed to revoke \(kind): HTTP \(status): \(message)"
        }
    }
}
