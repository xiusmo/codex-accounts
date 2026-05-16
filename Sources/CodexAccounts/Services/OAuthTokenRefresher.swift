import Foundation

final class OAuthTokenRefresher {
    private let clientId = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let defaultEndpoint = "https://auth.openai.com/oauth/token"
    private let userAgent: String

    init(userAgent: String = "codex_cli_rs") {
        self.userAgent = userAgent
    }

    @discardableResult
    func refreshAuth(in homeDirectory: URL) async throws -> AuthDotJson {
        let authURL = homeDirectory.appendingPathComponent("auth.json")
        let data: Data
        do {
            data = try Data(contentsOf: authURL)
        } catch {
            throw OAuthTokenRefreshError.readAuth(path: authURL.path, cause: RawErrorText.string(error))
        }

        var auth: AuthDotJson
        do {
            auth = try JSONDecoder().decode(AuthDotJson.self, from: data)
        } catch {
            throw OAuthTokenRefreshError.decodeAuth(path: authURL.path, cause: RawErrorText.string(error))
        }

        guard var tokens = auth.tokens else {
            throw OAuthTokenRefreshError.missingTokens(path: authURL.path)
        }
        guard !tokens.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OAuthTokenRefreshError.emptyRefreshToken(path: authURL.path)
        }

        let response = try await requestRefresh(refreshToken: tokens.refreshToken)

        if let idToken = response.idToken {
            tokens.idToken = idToken
            if let accountId = JWT.parseIdTokenClaims(idToken)?.chatgptAccountId {
                tokens.accountId = accountId
            }
        }
        if let accessToken = response.accessToken {
            tokens.accessToken = accessToken
        }
        if let refreshToken = response.refreshToken {
            tokens.refreshToken = refreshToken
        }

        auth.tokens = tokens
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        auth.lastRefresh = iso.string(from: Date())

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let encoded = try encoder.encode(auth)
            try encoded.write(to: authURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authURL.path)
        } catch {
            throw OAuthTokenRefreshError.writeAuth(path: authURL.path, cause: RawErrorText.string(error))
        }

        return auth
    }

    private func requestRefresh(refreshToken: String) async throws -> RefreshResponse {
        var request = URLRequest(url: try endpoint())
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(RefreshRequest(
            clientId: clientId,
            grantType: "refresh_token",
            refreshToken: refreshToken
        ))

        let (body, response): (Data, URLResponse)
        do {
            (body, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OAuthTokenRefreshError.requestFailed(cause: RawErrorText.string(error))
        }

        guard let http = response as? HTTPURLResponse else {
            throw OAuthTokenRefreshError.noHTTPResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OAuthTokenRefreshError.http(statusCode: http.statusCode, body: RawErrorText.bodyString(body))
        }

        do {
            return try JSONDecoder().decode(RefreshResponse.self, from: body)
        } catch {
            throw OAuthTokenRefreshError.decodeResponse(body: RawErrorText.bodyString(body), cause: RawErrorText.string(error))
        }
    }

    private func endpoint() throws -> URL {
        let raw = ProcessInfo.processInfo.environment["CODEX_REFRESH_TOKEN_URL_OVERRIDE"] ?? defaultEndpoint
        guard let url = URL(string: raw) else {
            throw OAuthTokenRefreshError.invalidEndpoint(raw)
        }
        return url
    }
}

private struct RefreshRequest: Encodable {
    let clientId: String
    let grantType: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case grantType = "grant_type"
        case refreshToken = "refresh_token"
    }
}

private struct RefreshResponse: Decodable {
    let idToken: String?
    let accessToken: String?
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

enum OAuthTokenRefreshError: Error, CustomStringConvertible {
    case readAuth(path: String, cause: String)
    case decodeAuth(path: String, cause: String)
    case missingTokens(path: String)
    case emptyRefreshToken(path: String)
    case requestFailed(cause: String)
    case noHTTPResponse
    case http(statusCode: Int, body: String)
    case decodeResponse(body: String, cause: String)
    case writeAuth(path: String, cause: String)
    case invalidEndpoint(String)

    var description: String {
        switch self {
        case let .readAuth(path, cause):
            return "\(path): \(cause)"
        case let .decodeAuth(path, cause):
            return "\(path): \(cause)"
        case let .missingTokens(path):
            return "\(path): tokens missing"
        case let .emptyRefreshToken(path):
            return "\(path): refresh_token empty"
        case let .requestFailed(cause):
            return cause
        case .noHTTPResponse:
            return "no HTTP response"
        case let .http(statusCode, body):
            return "HTTP \(statusCode): \(body)"
        case let .decodeResponse(body, cause):
            return "\(cause)\n\(body)"
        case let .writeAuth(path, cause):
            return "\(path): \(cause)"
        case let .invalidEndpoint(raw):
            return "invalid refresh endpoint: \(raw)"
        }
    }
}
