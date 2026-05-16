import Foundation

/// In-memory representation of one managed Codex account.
struct Account: Identifiable, Equatable {
    /// Filesystem directory name under ~/.codex.accounts/. Sanitized email by default.
    let directoryName: String
    /// Best-effort email pulled out of the id_token JWT.
    let email: String?
    /// Plan label ("pro", "plus", ...) pulled out of the id_token JWT.
    let planType: String?
    /// ChatGPT-Account-Id header value, pulled out of the id_token JWT.
    let chatgptAccountId: String?
    /// Whether this account is currently the active one (matches ~/.codex.accounts/active).
    let isActive: Bool
    /// Absolute path to the per-account CODEX_HOME.
    let homeDirectory: URL
    /// Whether the access_token has expired according to its JWT `exp`.
    let accessTokenExpired: Bool

    var id: String { directoryName }

    var displayName: String { email ?? directoryName }
}

/// A Codex auth.json found outside the managed account pool that can be imported.
struct CodexImportCandidate: Identifiable, Equatable {
    let sourceURL: URL
    let email: String?
    let planType: String?
    let chatgptAccountId: String?
    let sourceLabel: String

    var id: String { sourceURL.path }
    var displayName: String { email ?? chatgptAccountId ?? sourceLabel }
}

/// Per-account usage state, refreshed when the popover opens or the user hits refresh.
enum UsageState: Equatable {
    case idle
    case loading
    case loaded(plan: String?, primary: WindowSnapshot?, secondary: WindowSnapshot?)
    /// Token refresh failed, or the backend rejected the current auth.
    case tokenExpired(String?)
    /// Refresh token was rejected as invalid/reused/revoked.
    case authInvalid(String?)
    /// auth.json missing or no oauth tokens (API key only account).
    case noToken
    case failed(String)
}

struct WindowSnapshot: Equatable {
    let usedPercent: Double
    let resetAt: Date?
    let windowSeconds: Int?
}
