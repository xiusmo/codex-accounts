import Foundation

/// Talks to the (undocumented) ChatGPT backend endpoint that codex itself uses
/// to display rate limits. Token refresh is handled by AppState so this client
/// only reports auth expiry/rejection as a signal.
final class UsageClient {
    private let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private let userAgent: String

    init(userAgent: String = "codex_cli_rs") {
        self.userAgent = userAgent
    }

    func fetchUsage(for account: Account) async -> UsageState {
        let authURL = account.homeDirectory.appendingPathComponent("auth.json")
        do {
            let data = try Data(contentsOf: authURL)
            let auth = try JSONDecoder().decode(AuthDotJson.self, from: data)
            guard let tokens = auth.tokens else { return .noToken }
            if let exp = JWT.parseExpiration(tokens.accessToken), exp < Date() {
                return .tokenExpired(nil)
            }
            let claims = JWT.parseIdTokenClaims(tokens.idToken)
            let accountId = tokens.accountId ?? claims?.chatgptAccountId
            let fedramp = claims?.chatgptAccountIsFedramp ?? false

            var req = URLRequest(url: endpoint)
            req.httpMethod = "GET"
            req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
            if let accountId { req.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id") }
            if fedramp { req.setValue("true", forHTTPHeaderField: "X-OpenAI-Fedramp") }
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("application/json", forHTTPHeaderField: "Accept")

            let (body, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                return .failed("no HTTP response")
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return .tokenExpired(RawErrorText.http(statusCode: http.statusCode, body: body))
            }
            if !(200..<300).contains(http.statusCode) {
                return .failed(RawErrorText.http(statusCode: http.statusCode, body: body))
            }
            let payload = try JSONDecoder().decode(UsagePayload.self, from: body)
            return makeLoaded(payload: payload)
        } catch {
            return .failed(RawErrorText.string(error))
        }
    }

    private func makeLoaded(payload: UsagePayload) -> UsageState {
        let primary = payload.rateLimit?.primaryWindow.map(snapshot(from:))
        let secondary = payload.rateLimit?.secondaryWindow.map(snapshot(from:))
        return .loaded(plan: payload.planType, primary: primary, secondary: secondary)
    }

    private func snapshot(from window: RateLimitWindow) -> WindowSnapshot {
        let resetDate: Date? = {
            if let resetAt = window.resetAt {
                return Date(timeIntervalSince1970: TimeInterval(resetAt))
            }
            if let after = window.resetAfterSeconds {
                return Date().addingTimeInterval(TimeInterval(after))
            }
            return nil
        }()
        return WindowSnapshot(
            usedPercent: window.usedPercent,
            resetAt: resetDate,
            windowSeconds: window.limitWindowSeconds
        )
    }
}
