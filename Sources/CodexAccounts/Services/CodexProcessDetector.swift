import Foundation
import Darwin

/// Best-effort detection of running codex CLI processes — used to warn the user
/// before switching accounts, because a running codex could race-write its rotating
/// refresh_token into the wrong account's auth.json.
///
/// With the shim + CODEX_HOME isolation strategy this is mostly a belt-and-suspenders
/// check: each codex process is locked to its own CODEX_HOME at start, so switching
/// the active pointer cannot misdirect its writes. We still surface a soft notice so
/// the user knows the currently-running codex won't pick up the new selection.
enum CodexProcessDetector {
    struct Hit: Sendable {
        let pid: Int32
        let command: String
    }

    struct TerminationFailure: Sendable, CustomStringConvertible {
        let pid: Int32
        let command: String
        let code: Int32

        var description: String {
            "kill \(pid) \(command): errno \(code)"
        }
    }

    static func runningInstances() async -> [Hit] {
        await Task.detached(priority: .utility) {
            runningInstancesBlocking()
        }.value
    }

    private static func runningInstancesBlocking() -> [Hit] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var hits: [Hit] = []
        for raw in output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let scanner = Scanner(string: line)
            scanner.charactersToBeSkipped = nil
            guard let pid = scanner.scanInt32() else { continue }
            _ = scanner.scanCharacters(from: .whitespaces)
            let command = String(line[scanner.currentIndex...])
            let basename = (command as NSString).lastPathComponent
            guard basename == "codex" else { continue }
            guard pid != ownPID else { continue }
            hits.append(Hit(pid: pid, command: command))
        }
        return hits
    }

    static func terminate(_ hits: [Hit]) async -> [TerminationFailure] {
        await Task.detached(priority: .utility) {
            hits.compactMap { hit in
                guard Darwin.kill(hit.pid, SIGTERM) != 0 else { return nil }
                let code = errno
                guard code != ESRCH else { return nil }
                return TerminationFailure(pid: hit.pid, command: hit.command, code: code)
            }
        }.value
    }
}
