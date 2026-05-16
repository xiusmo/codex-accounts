import Foundation

enum AccountStoreError: Error, LocalizedError {
    case noAuthJson
    case directoryConflict(String)
    case accountNotFound(String)
    case invalidAlias(String)
    case duplicateAlias(String)

    var errorDescription: String? {
        switch self {
        case .noAuthJson: return "auth.json not found in account directory"
        case .directoryConflict(let name): return "Account directory '\(name)' already exists."
        case .accountNotFound(let name): return "Account not found: \(name)"
        case .invalidAlias(let alias): return "Invalid account alias: \(alias)"
        case .duplicateAlias(let alias): return "Duplicate account alias: \(alias)"
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
    private struct LoadedAccount {
        let directoryName: String
        let email: String?
        let planType: String?
        let chatgptAccountId: String?
        let isActive: Bool
        let homeDirectory: URL
        let accessTokenExpired: Bool

        var displayName: String { email ?? directoryName }
        var maskedDisplayName: String { EmailPrivacy.masked(email ?? directoryName) }
    }

    let baseURL: URL
    private let fm = FileManager.default
    private let aliasCandidates = [
        "ash", "bay", "cyan", "dew", "elm", "fox", "gold", "ivy", "jet", "mint",
        "nova", "oak", "rain", "sage", "sky", "sun", "teal", "wave", "zen",
        "ace", "arc", "bee", "bit", "dot", "fig", "ink", "map", "orb", "pod",
        "ray", "sea", "tap", "tea", "way", "zip"
    ]

    init(baseURL: URL? = nil) {
        if let base = baseURL {
            self.baseURL = base
        } else {
            self.baseURL = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".codex.accounts", isDirectory: true)
        }
    }

    var activeFileURL: URL { baseURL.appendingPathComponent("active") }
    var aliasIndexURL: URL { baseURL.appendingPathComponent("accounts.tsv") }

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
    /// Missing aliases are generated from short neutral words and persisted for the shim.
    func loadAll() throws -> [Account] {
        try ensureBaseDirectory()
        let activeName = readActiveName()
        let entries = try fm.contentsOfDirectory(at: baseURL,
                                                 includingPropertiesForKeys: [.isDirectoryKey],
                                                 options: [.skipsHiddenFiles])
        var loaded: [LoadedAccount] = []
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
            loaded.append(LoadedAccount(
                directoryName: dirName,
                email: claims?.email,
                planType: claims?.chatgptPlanType,
                chatgptAccountId: claims?.chatgptAccountId,
                isActive: dirName == activeName,
                homeDirectory: entry,
                accessTokenExpired: expired
            ))
        }
        let aliases = try reconcileAliases(for: loaded)
        let accounts = loaded.map { row in
            Account(
                directoryName: row.directoryName,
                alias: aliases[row.directoryName] ?? row.directoryName,
                email: row.email,
                planType: row.planType,
                chatgptAccountId: row.chatgptAccountId,
                isActive: row.isActive,
                homeDirectory: row.homeDirectory,
                accessTokenExpired: row.accessTokenExpired
            )
        }
        return accounts.sorted { a, b in
            if a.isActive != b.isActive { return a.isActive }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    func setAlias(_ rawAlias: String, for directoryName: String) throws {
        try ensureBaseDirectory()
        guard let alias = normalizedAlias(rawAlias) else {
            throw AccountStoreError.invalidAlias(rawAlias)
        }

        let accounts = try loadAll()
        guard accounts.contains(where: { $0.directoryName == directoryName }) else {
            throw AccountStoreError.accountNotFound(directoryName)
        }
        if accounts.contains(where: { $0.directoryName != directoryName && $0.alias.lowercased() == alias }) {
            throw AccountStoreError.duplicateAlias(alias)
        }

        let rewritten = accounts.map { account in
            LoadedAccount(
                directoryName: account.directoryName,
                email: account.email,
                planType: account.planType,
                chatgptAccountId: account.chatgptAccountId,
                isActive: account.isActive,
                homeDirectory: account.homeDirectory,
                accessTokenExpired: account.accessTokenExpired
            )
        }
        var aliases = Dictionary(uniqueKeysWithValues: accounts.map { ($0.directoryName, $0.alias) })
        aliases[directoryName] = alias
        try writeAliasIndex(rows: rewritten, aliases: aliases)
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

    private func reconcileAliases(for rows: [LoadedAccount]) throws -> [String: String] {
        var aliases: [String: String] = [:]
        var used = Set<String>()
        var didChange = false
        let existing = readAliasIndex()
        let validDirectories = Set(rows.map(\.directoryName))

        for row in rows {
            guard let raw = existing[row.directoryName],
                  let alias = normalizedAlias(raw),
                  !used.contains(alias) else {
                didChange = true
                continue
            }
            aliases[row.directoryName] = alias
            used.insert(alias)
            if raw != alias { didChange = true }
        }

        for row in rows where aliases[row.directoryName] == nil {
            let alias = nextAlias(used: &used)
            aliases[row.directoryName] = alias
            didChange = true
        }

        if existing.keys.contains(where: { !validDirectories.contains($0) }) {
            didChange = true
        }

        if didChange {
            try writeAliasIndex(rows: rows, aliases: aliases)
        }
        return aliases
    }

    private func readAliasIndex() -> [String: String] {
        guard let raw = try? String(contentsOf: aliasIndexURL, encoding: .utf8) else {
            return [:]
        }

        var aliases: [String: String] = [:]
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("#") { continue }
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 2 else { continue }
            let alias = String(parts[0])
            let directoryName = String(parts[1])
            guard !alias.isEmpty, !directoryName.isEmpty else { continue }
            aliases[directoryName] = alias
        }
        return aliases
    }

    private func writeAliasIndex(rows: [LoadedAccount], aliases: [String: String]) throws {
        let sortedRows = rows.sorted {
            (aliases[$0.directoryName] ?? "").localizedCaseInsensitiveCompare(
                aliases[$1.directoryName] ?? ""
            ) == .orderedAscending
        }
        var lines = ["# alias\tdirectory\tdisplay"]
        for row in sortedRows {
            guard let alias = aliases[row.directoryName] else { continue }
            lines.append("\(alias)\t\(row.directoryName)\t\(row.maskedDisplayName)")
        }
        let contents = lines.joined(separator: "\n") + "\n"
        try contents.write(to: aliasIndexURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: aliasIndexURL.path)
    }

    private func normalizedAlias(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard (2...12).contains(value.count) else { return nil }
        guard let first = value.first, first != "-", first != "_" else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_")
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return value
    }

    private func nextAlias(used: inout Set<String>) -> String {
        var suffix = 1
        while true {
            for word in aliasCandidates {
                let candidate = suffix == 1 ? word : "\(word)\(suffix)"
                if used.insert(candidate).inserted {
                    return candidate
                }
            }
            suffix += 1
        }
    }

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
