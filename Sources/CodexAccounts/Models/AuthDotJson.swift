import Foundation

/// Mirror of `$CODEX_HOME/auth.json` produced by the codex CLI.
struct AuthDotJson: Codable {
    var authMode: String? = nil
    var openaiApiKey: String? = nil
    var tokens: TokenData? = nil
    var lastRefresh: String? = nil

    enum CodingKeys: String, CodingKey {
        case authMode = "auth_mode"
        case openaiApiKey = "OPENAI_API_KEY"
        case tokens
        case lastRefresh = "last_refresh"
    }
}

struct TokenData: Codable {
    var idToken: String
    var accessToken: String
    var refreshToken: String
    var accountId: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case accountId = "account_id"
    }
}
