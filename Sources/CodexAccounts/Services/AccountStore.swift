import Foundation

enum AccountStoreError: Error, LocalizedError {
    case noAuthJson
    case directoryConflict(String)

    var errorDescription: String? {
        switch self {
        case .noAuthJson: return "auth.json not found in account directory"
        case .directoryConflict(let name): return "Account directory '\(name)' already exists."
        }
    }
}

/// Manages the on-disk account pool under `~/.codex.accounts/`.
///
/// Directory layout:
///   ~/.codex.accounts/
///   ├── active                       <- single line, name of active account dir
///   ├── alice@gmail.com/             <- per-account CODEX_HOME
///   │   └── auth.json
///   └── work@company.com/
///       └── auth.json
final class AccountStore {
    let baseURL: URL
    private let fm = FileManager.default

    init(baseURL: URL? = nil) {
        if let base = baseURL {
            self.baseURL = base
        } else {
            self.baseURL = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".codex.accounts", isDirectory: true)
        }
    }

    var activeFileURL: URL { baseURL.appendingPathComponent("active") }

    /// Ensure the base directory exists. Safe to call repeatedly.
    func ensureBaseDirectory() throws {
        if !fm.fileExists(atPath: baseURL.path) {
            try fm.createDirectory(at: baseURL, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        }
    }

    /// Read the currently active account directory name, if any.
    func readActiveName() -> String? {
        guard let raw = try? String(contentsOf: activeFileURL, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Atomically set the active account.
    func setActive(_ directoryName: String) throws {
        try ensureBaseDirectory()
        let target = baseURL.appendingPathComponent(directoryName, isDirectory: true)
        guard fm.fileExists(atPath: target.path) else {
            throw AccountStoreError.directoryConflict(directoryName)
        }
        try (directoryName + "\n").write(to: activeFileURL, atomically: true, encoding: .utf8)
    }

    /// Scan the base directory and produce Account values for every subdirectory
    /// containing an auth.json. Accounts are sorted: active first, then by display name.
    func loadAll() throws -> [Account] {
        try ensureBaseDirectory()
        let activeName = readActiveName()
        let entries = try fm.contentsOfDirectory(at: baseURL,
                                                 includingPropertiesForKeys: [.isDirectoryKey],
                                                 options: [.skipsHiddenFiles])
        var accounts: [Account] = []
        for entry in entries {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let authURL = entry.appendingPathComponent("auth.json")
            guard fm.fileExists(atPath: authURL.path) else { continue }
            let dirName = entry.lastPathComponent
            let authJson = (try? readAuth(at: authURL)) ?? AuthDotJson()
            let claims = authJson.tokens.flatMap { JWT.parseIdTokenClaims($0.idToken) }
            let expired: Bool = {
                guard let token = authJson.tokens?.accessToken,
                      let exp = JWT.parseExpiration(token) else { return false }
                return exp < Date()
            }()
            accounts.append(Account(
                directoryName: dirName,
                email: claims?.email,
                planType: claims?.chatgptPlanType,
                chatgptAccountId: claims?.chatgptAccountId,
                isActive: dirName == activeName,
                homeDirectory: entry,
                accessTokenExpired: expired
            ))
        }
        return accounts.sorted { a, b in
            if a.isActive != b.isActive { return a.isActive }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    func discoverCodexImportCandidates(managedAccounts: [Account]) -> [CodexImportCandidate] {
        let managedKeys = Set(managedAccounts.flatMap { accountKeys(email: $0.email, accountId: $0.chatgptAccountId) })
        var seenKeys = Set<String>()
        var candidates: [CodexImportCandidate] = []

        for url in standardCodexAuthURLs() {
            guard fm.fileExists(atPath: url.path),
                  let authJson = try? readAuth(at: url) else { continue }
            let claims = authJson.tokens.flatMap { JWT.parseIdTokenClaims($0.idToken) }
            let keys = accountKeys(email: claims?.email, accountId: claims?.chatgptAccountId)
            if !keys.isEmpty && !managedKeys.isDisjoint(with: Set(keys)) {
                continue
            }
            if !keys.isEmpty && !seenKeys.isDisjoint(with: Set(keys)) {
                continue
            }

            keys.forEach { seenKeys.insert($0) }
            candidates.append(CodexImportCandidate(
                sourceURL: url,
                email: claims?.email,
                planType: claims?.chatgptPlanType,
                chatgptAccountId: claims?.chatgptAccountId,
                sourceLabel: abbreviateHome(url.path)
            ))
        }

        return candidates
    }

    /// Persist a freshly-issued auth payload into a new (or existing) account directory.
    /// The directory name is derived from the email when available, falling back to a stable token.
    /// Returns the directory name actually used.
    @discardableResult
    func saveNewAccount(authJson: AuthDotJson, preferredName: String? = nil) throws -> String {
        try ensureBaseDirectory()
        let claims = authJson.tokens.flatMap { JWT.parseIdTokenClaims($0.idToken) }
        let baseName = preferredName ?? sanitize(claims?.email ?? "codex-account-\(Int(Date().timeIntervalSince1970))")
        let dir = baseURL.appendingPathComponent(baseName, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        }
        try writeAuth(authJson, to: dir.appendingPathComponent("auth.json"))
        return baseName
    }

    func readAuth(directoryName: String) throws -> AuthDotJson {
        try ensureBaseDirectory()
        let authURL = baseURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("auth.json")
        guard fm.fileExists(atPath: authURL.path) else {
            throw AccountStoreError.noAuthJson
        }
        return try readAuth(at: authURL)
    }

    @discardableResult
    func importAuth(from authURL: URL) throws -> String {
        let authJson = try readAuth(at: authURL)
        return try saveNewAccount(authJson: authJson)
    }

    func removeAccount(directoryName: String) throws {
        try ensureBaseDirectory()
        let wasActive = readActiveName() == directoryName
        let dir = baseURL.appendingPathComponent(directoryName, isDirectory: true)
        if fm.fileExists(atPath: dir.path) {
            try fm.removeItem(at: dir)
        }
        if wasActive {
            try promoteNextActiveAccount()
        }
    }

    // MARK: - private

    private func readAuth(at url: URL) throws -> AuthDotJson {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AuthDotJson.self, from: data)
    }

    private func writeAuth(_ auth: AuthDotJson, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(auth)
        try data.write(to: url, options: [.atomic])
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func promoteNextActiveAccount() throws {
        let remaining = try loadAll()
        if let next = remaining.first {
            try setActive(next.directoryName)
        } else if fm.fileExists(atPath: activeFileURL.path) {
            try fm.removeItem(at: activeFileURL)
        }
    }

    private func standardCodexAuthURLs() -> [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return [
            home.appendingPathComponent(".codex/auth.json"),
            home.appendingPathComponent(".codex/auth/auth.json")
        ]
    }

    private func accountKeys(email: String?, accountId: String?) -> [String] {
        var keys: [String] = []
        if let accountId, !accountId.isEmpty {
            keys.append("account:\(accountId)")
        }
        if let email, !email.isEmpty {
            keys.append("email:\(email.lowercased())")
        }
        return keys
    }

    private func abbreviateHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func sanitize(_ raw: String) -> String {
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_@+")
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let cleaned = String(scalars)
        return cleaned.isEmpty ? "codex-account" : cleaned
    }
}
