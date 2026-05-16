import Foundation

/// Manages the `codex` shim that injects `CODEX_HOME` into every invocation
/// according to ~/.codex.accounts/active.
final class ShimInstaller {
    /// Fallback location used only when we cannot safely interpose at the active codex entry.
    let fallbackShimURL: URL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".local/bin/codex")

    /// Marker we embed inside the shim so we can recognize it during status checks.
    private let marker = "# codex-accounts shim"
    private let versionMarker = "# codex-accounts shim-v2"
    private let originalSymlinkMarker = "# codex-accounts original-symlink: "

    enum InstalledKind: Equatable {
        case missing
        case ours(realCodex: String)
        case foreign
    }

    struct Status {
        let installed: InstalledKind
        /// Where this app will install the codex shim.
        let installPath: String
        /// Path to the real codex binary we discovered (or nil if not found).
        let detectedRealCodex: String?
        /// Whether the `codex` resolved by the user's shell is already our shim.
        let pathPrecedenceOK: Bool
        /// Whether an existing shim predates the current template.
        let shimNeedsUpdate: Bool
        /// User's interactive PATH (after `zsh -l -c 'echo $PATH'`).
        let interactivePATH: String
    }

    // MARK: - Public API

    func currentStatus() -> Status {
        let interactivePATH = readInteractivePATH()
        let effectiveCodex = firstCodex(in: interactivePATH)
        let effectiveInstalled = effectiveCodex.map { readInstalledKind(at: $0) }
        let detected = realCodexPath(from: effectiveInstalled) ?? findRealCodex(in: interactivePATH)
        let installURL = recommendedShimURL(
            interactivePATH: interactivePATH,
            effectiveCodex: effectiveCodex,
            realCodex: detected
        )
        return Status(
            installed: readInstalledKind(at: installURL),
            installPath: installURL.path,
            detectedRealCodex: detected,
            pathPrecedenceOK: effectiveCodex.map { isProbablyShim(path: $0.path) } ?? false,
            shimNeedsUpdate: shimNeedsUpdate(at: installURL),
            interactivePATH: interactivePATH
        )
    }

    /// Install the shim. `realCodexPath` is baked into the script so the shim
    /// has zero PATH-scanning logic at runtime — fast and predictable.
    func install(realCodexPath: String) throws {
        let status = currentStatus()
        let targetURL = URL(fileURLWithPath: status.installPath)
        let originalSymlink = symlinkDestination(at: targetURL)
        let executableCodexPath = resolvedRealCodexPath(
            requestedRealCodexPath: realCodexPath,
            targetURL: targetURL,
            originalSymlink: originalSymlink
        )

        try ensureParentDir(for: targetURL)
        let template = try shimTemplate()
        let rendered = template
            .replacingOccurrences(of: "__CODEX_REAL_PATH__", with: executableCodexPath)
            .replacingOccurrences(of: "__CODEX_ORIGINAL_SYMLINK__", with: originalSymlink ?? "")

        if FileManager.default.fileExists(atPath: targetURL.path) || isSymlink(targetURL) {
            try FileManager.default.removeItem(at: targetURL)
        }
        try rendered.write(to: targetURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: targetURL.path)

        // Remove the old fallback shim if we managed to install at the effective codex path.
        if targetURL.path != fallbackShimURL.path,
           case .ours = readInstalledKind(at: fallbackShimURL) {
            try? removeShim(at: fallbackShimURL)
        }
    }

    func uninstall() throws {
        let status = currentStatus()
        let targets = [
            URL(fileURLWithPath: status.installPath),
            firstCodex(in: status.interactivePATH),
            fallbackShimURL
        ].compactMap { $0 }

        var seen = Set<String>()
        for target in targets where seen.insert(target.path).inserted {
            if case .ours = readInstalledKind(at: target) {
                try removeShim(at: target)
            }
        }
    }

    // MARK: - Internals

    private func ensureParentDir(for url: URL) throws {
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
    }

    private func shimTemplate() throws -> String {
        if let url = Bundle.module.url(forResource: "shim", withExtension: "sh"),
           let contents = try? String(contentsOf: url, encoding: .utf8) {
            return contents
        }
        // Fallback: bake the template into the binary so the app still works if
        // the bundle copy is missing (rare, but defensive).
        return Self.embeddedTemplate
    }

    private func readInstalledKind(at url: URL) -> InstalledKind {
        guard FileManager.default.fileExists(atPath: url.path) || isSymlink(url) else { return .missing }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return .foreign }
        guard contents.contains(marker) else { return .foreign }
        let pattern = "REAL_CODEX=\""
        guard let range = contents.range(of: pattern) else { return .foreign }
        let rest = contents[range.upperBound...]
        guard let endQuote = rest.firstIndex(of: "\"") else { return .foreign }
        let real = String(rest[..<endQuote])
        return .ours(realCodex: real)
    }

    private func shimNeedsUpdate(at url: URL) -> Bool {
        guard case .ours = readInstalledKind(at: url) else { return false }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return true }
        return !contents.contains(versionMarker)
    }

    private func findRealCodex(in pathString: String) -> String? {
        let extras = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        var seen = Set<String>()
        var ordered: [String] = []
        for dir in pathString.split(separator: ":").map(String.init) + extras {
            if dir.isEmpty { continue }
            if seen.insert(dir).inserted { ordered.append(dir) }
        }
        for dir in ordered {
            let candidate = (dir as NSString).appendingPathComponent("codex")
            guard FileManager.default.isExecutableFile(atPath: candidate) else { continue }
            if isProbablyShim(path: candidate) { continue }
            return candidate
        }
        return nil
    }

    private func firstCodex(in pathString: String) -> URL? {
        for dir in pathString.split(separator: ":").map(String.init) {
            if dir.isEmpty { continue }
            let candidate = (dir as NSString).appendingPathComponent("codex")
            guard FileManager.default.isExecutableFile(atPath: candidate) else { continue }
            return URL(fileURLWithPath: candidate)
        }
        return nil
    }

    private func realCodexPath(from installed: InstalledKind?) -> String? {
        guard case let .ours(realCodex) = installed else { return nil }
        return realCodex
    }

    private func recommendedShimURL(
        interactivePATH: String,
        effectiveCodex: URL?,
        realCodex: String?
    ) -> URL {
        if let effectiveCodex {
            if case .ours = readInstalledKind(at: effectiveCodex) {
                return effectiveCodex
            }
            if canInterpose(at: effectiveCodex) {
                return effectiveCodex
            }
        }

        let dirs = interactivePATH.split(separator: ":").map(String.init)
        let fallbackDir = fallbackShimURL.deletingLastPathComponent().path
        if let fallbackIndex = dirs.firstIndex(of: fallbackDir) {
            let realIndex = realCodex
                .map { ($0 as NSString).deletingLastPathComponent }
                .flatMap { dirs.firstIndex(of: $0) }
            if realIndex.map({ fallbackIndex < $0 }) ?? true {
                return fallbackShimURL
            }
        }

        return fallbackShimURL
    }

    private func canInterpose(at url: URL) -> Bool {
        let parent = url.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else { return false }
        return symlinkDestination(at: url) != nil || isProbablyShim(path: url.path)
    }

    private func resolvedRealCodexPath(
        requestedRealCodexPath: String,
        targetURL: URL,
        originalSymlink: String?
    ) -> String {
        if let originalSymlink,
           requestedRealCodexPath == targetURL.path {
            return resolvedSymlinkDestination(
                originalSymlink,
                relativeTo: targetURL.deletingLastPathComponent()
            ).path
        }
        return requestedRealCodexPath
    }

    private func isProbablyShim(path: String) -> Bool {
        guard let head = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return false }
        defer { try? head.close() }
        let data = head.readData(ofLength: 512)
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains(marker)
    }

    private func removeShim(at url: URL) throws {
        let originalSymlink = originalSymlinkDestination(fromShimAt: url)
        let realCodex = realCodexPath(from: readInstalledKind(at: url))
        try FileManager.default.removeItem(at: url)
        if let originalSymlink, !originalSymlink.isEmpty {
            try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: originalSymlink)
        } else if url.path != fallbackShimURL.path, let realCodex, !realCodex.isEmpty {
            try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: realCodex)
        }
    }

    private func symlinkDestination(at url: URL) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)
    }

    private func resolvedSymlinkDestination(_ destination: String, relativeTo parent: URL) -> URL {
        if destination.hasPrefix("/") {
            return URL(fileURLWithPath: destination)
        }
        return parent.appendingPathComponent(destination).standardizedFileURL
    }

    private func originalSymlinkDestination(fromShimAt url: URL) -> String? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        guard let line = contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first(where: { $0.hasPrefix(originalSymlinkMarker) }) else {
            return nil
        }
        let value = String(line.dropFirst(originalSymlinkMarker.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func isSymlink(_ url: URL) -> Bool {
        symlinkDestination(at: url) != nil
    }

    /// Spawn the user's login shell to read the PATH they actually use day-to-day.
    /// Falls back to the process env's PATH if the shell can't be invoked.
    private func readInteractivePATH() -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: shell)
        task.arguments = ["-l", "-c", "printf %s \"$PATH\""]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0,
               let value = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
               !value.isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            // fall through
        }
        return ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
    }

    // Embedded fallback identical to Resources/shim.sh — kept in sync manually.
    private static let embeddedTemplate = """
    #!/bin/sh
    # codex-accounts shim — generated, do not edit by hand.
    # codex-accounts shim-v2
    # codex-accounts original-symlink: __CODEX_ORIGINAL_SYMLINK__
    set -e
    ACCOUNTS_DIR="${CODEX_ACCOUNTS_DIR:-$HOME/.codex.accounts}"
    ACTIVE_FILE="$ACCOUNTS_DIR/active"
    INDEX_FILE="$ACCOUNTS_DIR/accounts.tsv"
    REAL_CODEX="__CODEX_REAL_PATH__"

    read_active() {
        if [ -r "$ACTIVE_FILE" ]; then
            head -n1 "$ACTIVE_FILE" 2>/dev/null | tr -d '[:space:]' || true
        fi
    }

    lookup_by_alias() {
        key="$1"
        field="$2"
        if [ -r "$INDEX_FILE" ]; then
            awk -F '\\t' -v key="$key" -v field="$field" 'tolower($1) == tolower(key) { print $field; exit }' "$INDEX_FILE"
        fi
    }

    lookup_by_dir() {
        key="$1"
        field="$2"
        if [ -r "$INDEX_FILE" ]; then
            awk -F '\\t' -v key="$key" -v field="$field" '$2 == key { print $field; exit }' "$INDEX_FILE"
        fi
    }

    print_accounts() {
        active="$(read_active)"
        if [ -r "$INDEX_FILE" ]; then
            awk -F '\\t' -v active="$active" '
                /^#/ { next }
                NF >= 2 {
                    display = (NF >= 3 && $3 != "") ? $3 : $2
                    marker = ($2 == active) ? "  当前" : ""
                    printf "%-8s %s%s\\n", "@" $1, display, marker
                }
            ' "$INDEX_FILE"
        fi
    }

    SELECTED=""
    case "${1:-}" in
        @)
            print_accounts
            exit 0
            ;;
        @*)
            SELECTED="${1#@}"
            shift
            ;;
    esac
    if [ -z "$SELECTED" ] && [ "${1:-}" = "--account" ]; then
        if [ -z "${2:-}" ]; then
            echo "账号不存在: @" >&2
            exit 2
        fi
        SELECTED="${2:-}"
        shift 2
    fi
    if [ -z "$SELECTED" ] && [ "${1:-}" = "-A" ]; then
        if [ -z "${2:-}" ]; then
            echo "账号不存在: @" >&2
            exit 2
        fi
        SELECTED="${2:-}"
        shift 2
    fi
    if [ -z "$SELECTED" ] && [ -n "${CODEX_ACCOUNT:-}" ]; then
        SELECTED="${CODEX_ACCOUNT#@}"
    fi
    if [ -n "$SELECTED" ]; then
        ACCOUNT_DIR_NAME="$(lookup_by_alias "$SELECTED" 2)"
        if [ -z "$ACCOUNT_DIR_NAME" ]; then
            ACCOUNT_DIR_NAME="$SELECTED"
        fi
        if [ ! -d "$ACCOUNTS_DIR/$ACCOUNT_DIR_NAME" ]; then
            echo "账号不存在: @$SELECTED" >&2
            exit 2
        fi
        CODEX_HOME="$ACCOUNTS_DIR/$ACCOUNT_DIR_NAME"
        export CODEX_HOME
        ACCOUNT_ALIAS="$(lookup_by_dir "$ACCOUNT_DIR_NAME" 1)"
        ACCOUNT_DISPLAY="$(lookup_by_dir "$ACCOUNT_DIR_NAME" 3)"
        [ -n "$ACCOUNT_ALIAS" ] || ACCOUNT_ALIAS="$SELECTED"
        [ -n "$ACCOUNT_DISPLAY" ] || ACCOUNT_DISPLAY="$ACCOUNT_DIR_NAME"
        if [ "${CODEX_ACCOUNTS_QUIET:-0}" != "1" ]; then
            echo "Codex Accounts: $ACCOUNT_ALIAS · $ACCOUNT_DISPLAY" >&2
            if [ "${CODEX_ACCOUNTS_TITLE:-1}" != "0" ]; then
                printf '\\033]0;codex · %s\\007' "$ACCOUNT_ALIAS" >&2
            fi
        fi
    else
        ACTIVE="$(read_active)"
        if [ -n "$ACTIVE" ] && [ -d "$ACCOUNTS_DIR/$ACTIVE" ]; then
            CODEX_HOME="$ACCOUNTS_DIR/$ACTIVE"
            export CODEX_HOME
        fi
    fi
    if [ ! -x "$REAL_CODEX" ]; then
        echo "codex-accounts: real codex binary not found at $REAL_CODEX" >&2
        exit 127
    fi
    exec "$REAL_CODEX" "$@"
    """
}
