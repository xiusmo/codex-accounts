import Foundation

/// Shares selected account-neutral parts of multiple CODEX_HOME directories.
///
/// Account credentials, logs, environment files, installation identity, and
/// process-local scratch space intentionally stay per account. History/state/cache
/// and config are separate toggles because config changes Codex behavior.
final class SharedCodexData {
    enum ShareError: Error, LocalizedError {
        case unsafeRelativePath(String)

        var errorDescription: String? {
            switch self {
            case .unsafeRelativePath(let path):
                return "Unsafe shared CODEX_HOME path: \(path)"
            }
        }
    }

    private enum ItemKind: Equatable {
        case directory
        case file
    }

    private struct Item {
        let relativePath: String
        let kind: ItemKind
    }

    private let baseURL: URL
    private let sharedRoot: URL
    private let backupRoot: URL
    private let standardCodexHome: URL
    private let fm = FileManager.default

    private let dataItems: [Item] = [
        // Threads, resume metadata, goals, dynamic tools, jobs, and history.
        Item(relativePath: "sessions", kind: .directory),
        Item(relativePath: "archived_sessions", kind: .directory),
        Item(relativePath: "session_index.jsonl", kind: .file),
        Item(relativePath: "history.jsonl", kind: .file),
        Item(relativePath: "transcription-history.jsonl", kind: .file),
        Item(relativePath: "shell_snapshots", kind: .directory),
        Item(relativePath: "state_5.sqlite", kind: .file),
        Item(relativePath: "state_5.sqlite-wal", kind: .file),
        Item(relativePath: "state_5.sqlite-shm", kind: .file),

        // User-visible Codex state and installed capabilities.
        Item(relativePath: "memories", kind: .directory),
        Item(relativePath: "automations", kind: .directory),
        Item(relativePath: "worktrees", kind: .directory),
        Item(relativePath: "skills", kind: .directory),
        Item(relativePath: "plugins", kind: .directory),
        Item(relativePath: ".agents", kind: .directory),

        // Account-neutral assets and caches.
        Item(relativePath: "ambient-suggestions", kind: .directory),
        Item(relativePath: "generated_images", kind: .directory),
        Item(relativePath: "pets", kind: .directory),
        Item(relativePath: "avatars", kind: .directory),
        Item(relativePath: "themes", kind: .directory),
        Item(relativePath: "computer-use", kind: .directory),
        Item(relativePath: "cache", kind: .directory),
        Item(relativePath: "vendor_imports", kind: .directory),
        Item(relativePath: "models_cache.json", kind: .file),
        Item(relativePath: "version.json", kind: .file),
        Item(relativePath: ".personality_migration", kind: .file),
        Item(relativePath: ".tmp/plugins", kind: .directory),
        Item(relativePath: ".tmp/plugins.sha", kind: .file),
        Item(relativePath: ".tmp/bundled-marketplaces", kind: .directory),
        Item(relativePath: ".tmp/marketplaces", kind: .directory),
        Item(relativePath: ".tmp/legacy-primary-runtime-skills", kind: .directory),
        Item(relativePath: ".tmp/app-server-remote-plugin-sync-v1", kind: .file)
    ]
    private let configItems: [Item] = [
        Item(relativePath: "config.toml", kind: .file),
        Item(relativePath: "AGENTS.md", kind: .file),
        Item(relativePath: "hooks.json", kind: .file),
        Item(relativePath: "keybindings.json", kind: .file),
        Item(relativePath: "skills-role.toml", kind: .file),
        Item(relativePath: "rules", kind: .directory),
        Item(relativePath: "prompts", kind: .directory)
    ]

    init(accountsBaseURL: URL) {
        self.baseURL = accountsBaseURL
        self.sharedRoot = accountsBaseURL.appendingPathComponent(".shared-data", isDirectory: true)
        self.backupRoot = accountsBaseURL.appendingPathComponent(".local-backups", isDirectory: true)
        self.standardCodexHome = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex", isDirectory: true)
    }

    var sharedDirectoryPath: String { sharedRoot.path }

    func enable(for accounts: [Account]) throws {
        try ensureDirectory(baseURL)
        try ensureDirectory(sharedRoot)
        try seedSharedItemsFromStandardHome(dataItems)

        for account in accounts {
            try linkSharedItems(dataItems, in: account.homeDirectory, accountName: account.directoryName)
        }
    }

    func disable(for accounts: [Account]) throws {
        for account in accounts {
            try materializeSharedItems(dataItems, in: account.homeDirectory)
        }
    }

    func enableConfig(for accounts: [Account]) throws {
        try ensureDirectory(baseURL)
        try ensureDirectory(sharedRoot)
        try seedSharedItemsFromStandardHome(configItems)

        for account in accounts {
            try linkSharedItems(configItems, in: account.homeDirectory, accountName: account.directoryName)
        }
    }

    func disableConfig(for accounts: [Account]) throws {
        for account in accounts {
            try materializeSharedItems(configItems, in: account.homeDirectory)
        }
    }

    // MARK: - Enable

    private func seedSharedItemsFromStandardHome(_ items: [Item]) throws {
        guard itemExists(standardCodexHome) else { return }
        for item in items {
            let source = try url(standardCodexHome, item.relativePath)
            guard itemExists(source) else { continue }
            let target = try url(sharedRoot, item.relativePath)
            try ensureParentDirectory(for: target)
            let sourceKind = actualKind(of: source) ?? item.kind
            try mergeMissing(from: source, into: target, kind: sourceKind, relativePath: item.relativePath)
        }
    }

    private func linkSharedItems(_ items: [Item], in accountHome: URL, accountName: String) throws {
        for item in items {
            let linkURL = try url(accountHome, item.relativePath)
            let targetURL = try url(sharedRoot, item.relativePath)

            if isSymlink(linkURL, pointingTo: targetURL) {
                continue
            }

            let sourceKind = isSymlink(linkURL) ? nil : actualKind(of: linkURL)
            try prepareSharedTarget(
                targetURL,
                kind: sourceKind ?? item.kind,
                relativePath: item.relativePath
            )

            if itemExists(linkURL) {
                try absorbExistingItem(
                    linkURL,
                    into: targetURL,
                    kind: item.kind,
                    accountName: accountName,
                    relativePath: item.relativePath
                )
            }

            try ensureParentDirectory(for: linkURL)
            if itemExists(linkURL) {
                try fm.removeItem(at: linkURL)
            }
            try fm.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)
        }
    }

    private func absorbExistingItem(
        _ source: URL,
        into target: URL,
        kind: ItemKind,
        accountName: String,
        relativePath: String
    ) throws {
        if isSymlink(source) {
            try moveToBackup(source, accountName: accountName, relativePath: relativePath)
            return
        }

        if !itemExists(target) {
            try ensureParentDirectory(for: target)
            try fm.moveItem(at: source, to: target)
            return
        }

        let sourceKind = actualKind(of: source) ?? kind
        try mergeMissing(from: source, into: target, kind: sourceKind, relativePath: relativePath)
        try moveToBackup(source, accountName: accountName, relativePath: relativePath)
    }

    // MARK: - Disable

    private func materializeSharedItems(_ items: [Item], in accountHome: URL) throws {
        for item in items {
            let linkURL = try url(accountHome, item.relativePath)
            let targetURL = try url(sharedRoot, item.relativePath)
            guard isSymlink(linkURL, pointingTo: targetURL) else { continue }

            try fm.removeItem(at: linkURL)
            guard itemExists(targetURL) else { continue }

            try ensureParentDirectory(for: linkURL)
            let targetKind = actualKind(of: targetURL) ?? item.kind
            if targetKind == .directory {
                try copyDirectoryContents(from: targetURL, to: linkURL)
            } else {
                try fm.copyItem(at: targetURL, to: linkURL)
            }
        }
    }

    // MARK: - File movement

    private func prepareSharedTarget(_ target: URL, kind: ItemKind, relativePath: String) throws {
        if let targetKind = actualKind(of: target), targetKind != kind {
            try moveSharedItemToBackup(target, relativePath: relativePath)
        }

        switch kind {
        case .file:
            try ensureParentDirectory(for: target)
        case .directory:
            try ensureDirectory(target)
        }
    }

    private func mergeMissing(from source: URL, into target: URL, kind: ItemKind, relativePath: String) throws {
        let sourceKind = actualKind(of: source) ?? kind
        if let targetKind = actualKind(of: target), targetKind != sourceKind {
            try moveSharedItemToBackup(target, relativePath: relativePath)
        }

        switch sourceKind {
        case .file:
            if !itemExists(target) {
                try ensureParentDirectory(for: target)
                try fm.copyItem(at: source, to: target)
            }
        case .directory:
            try copyDirectoryContents(from: source, to: target)
        }
    }

    private func copyDirectoryContents(from source: URL, to target: URL) throws {
        try ensureDirectory(target)
        let children = try fm.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        for child in children {
            let destination = target.appendingPathComponent(child.lastPathComponent)
            if isSymlink(child) {
                if !itemExists(destination) {
                    try fm.copyItem(at: child, to: destination)
                }
                continue
            }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: child.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                try copyDirectoryContents(from: child, to: destination)
            } else if !itemExists(destination) {
                try ensureParentDirectory(for: destination)
                try fm.copyItem(at: child, to: destination)
            }
        }
    }

    private func moveToBackup(_ source: URL, accountName: String, relativePath: String) throws {
        let stamp = Self.backupTimestamp()
        let backupURL = backupRoot
            .appendingPathComponent(accountName, isDirectory: true)
            .appendingPathComponent(stamp, isDirectory: true)
            .appendingPathComponent(relativePath)
        try ensureParentDirectory(for: backupURL)
        try fm.moveItem(at: source, to: backupURL)
    }

    private func moveSharedItemToBackup(_ source: URL, relativePath: String) throws {
        let stamp = Self.backupTimestamp()
        let backupURL = backupRoot
            .appendingPathComponent("_shared", isDirectory: true)
            .appendingPathComponent(stamp, isDirectory: true)
            .appendingPathComponent(relativePath)
        try ensureParentDirectory(for: backupURL)
        try fm.moveItem(at: source, to: backupURL)
    }

    // MARK: - Path helpers

    private func url(_ root: URL, _ relativePath: String) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains(where: { $0 == ".." }) else {
            throw ShareError.unsafeRelativePath(relativePath)
        }
        return root.appendingPathComponent(relativePath)
    }

    private func ensureDirectory(_ url: URL) throws {
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue { return }
            try fm.removeItem(at: url)
        }
        try fm.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func ensureParentDirectory(for url: URL) throws {
        try ensureDirectory(url.deletingLastPathComponent())
    }

    private func itemExists(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            return true
        }
        return isSymlink(url)
    }

    private func actualKind(of url: URL) -> ItemKind? {
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            return isDir.boolValue ? .directory : .file
        }

        guard let destination = symlinkDestination(of: url, relativeTo: url.deletingLastPathComponent()) else {
            return nil
        }

        if fm.fileExists(atPath: destination.path, isDirectory: &isDir) {
            return isDir.boolValue ? .directory : .file
        }
        return nil
    }

    private func isSymlink(_ url: URL) -> Bool {
        (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private func isSymlink(_ url: URL, pointingTo target: URL) -> Bool {
        guard let destination = symlinkDestination(of: url, relativeTo: url.deletingLastPathComponent()) else {
            return false
        }
        return destination.standardizedFileURL.path == target.standardizedFileURL.path
    }

    private func symlinkDestination(of url: URL, relativeTo parent: URL) -> URL? {
        guard let raw = try? fm.destinationOfSymbolicLink(atPath: url.path) else { return nil }
        if raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw)
        }
        return parent.appendingPathComponent(raw)
    }

    private static func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
