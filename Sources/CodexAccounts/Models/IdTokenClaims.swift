import Foundation

/// Subset of claims we read out of the OAuth id_token JWT.
/// Codex puts the interesting fields under
/// `https://api.openai.com/auth` and `https://api.openai.com/profile`.
struct IdTokenClaims {
    var email: String?
    var chatgptPlanType: String?
    var chatgptUserId: String?
    var chatgptAccountId: String?
    var chatgptAccountIsFedramp: Bool
    var exp: Date?
}

/// Subset of claims we read out of the OAuth access_token JWT.
struct AccessTokenClaims {
    var exp: Date?
}
