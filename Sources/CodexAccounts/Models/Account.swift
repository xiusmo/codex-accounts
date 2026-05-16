import Foundation

/// In-memory representation of one managed Codex account.
struct Account: Identifiable, Equatable {
    /// Filesystem directory name under ~/.codex.accounts/. Sanitized email by default.
    let directoryName: String
    /// Short user-facing handle used by the shim, for example `codex @ash`.
    let alias: String
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
    var commandAlias: String { "@\(alias)" }
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
    case loaded(plan: String?, primary: WindowSnapshot?, secondary: WindowSnapshot?, additional: [AdditionalUsageSnapshot])
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

    var remainingPercent: Double {
        guard usedPercent.isFinite else { return 0 }
        return max(0, min(100, 100 - usedPercent))
    }
}

struct AdditionalUsageSnapshot: Equatable {
    let limitName: String?
    let meteredFeature: String?
    let primary: WindowSnapshot?
    let secondary: WindowSnapshot?

    var isSparkLimit: Bool {
        let identifiers = [limitName, meteredFeature]
            .compactMap { $0?.lowercased() }
        return identifiers.contains { value in
            value.contains("spark") || value == "codex_other"
        }
    }

    var displayName: String {
        guard let raw = limitName ?? meteredFeature else { return "Spark" }
        if raw.caseInsensitiveCompare("codex_other") == .orderedSame { return "Spark" }
        if raw.localizedCaseInsensitiveContains("spark") { return "Spark" }
        return raw
    }
}
