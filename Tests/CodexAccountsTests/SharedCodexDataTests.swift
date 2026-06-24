import Foundation
import XCTest
@testable import CodexAccounts

final class SharedCodexDataTests: XCTestCase {
    func testEnableMergesExistingJSONLLinesBeforeLinkingAccount() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sharedIndex = root
            .appendingPathComponent(".shared-data", isDirectory: true)
            .appendingPathComponent("session_index.jsonl")
        let accountHome = root.appendingPathComponent("account", isDirectory: true)
        let accountIndex = accountHome.appendingPathComponent("session_index.jsonl")

        try FileManager.default.createDirectory(
            at: sharedIndex.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: accountHome, withIntermediateDirectories: true)
        try "{\"id\":\"shared\"}\n".write(to: sharedIndex, atomically: true, encoding: .utf8)
        try "{\"id\":\"account\"}\n".write(to: accountIndex, atomically: true, encoding: .utf8)

        let account = Account(
            directoryName: "account",
            alias: "acct",
            email: nil,
            planType: nil,
            chatgptAccountId: nil,
            isActive: true,
            homeDirectory: accountHome,
            accessTokenExpired: false
        )

        try SharedCodexData(accountsBaseURL: root).enable(for: [account])

        let merged = try String(contentsOf: sharedIndex, encoding: .utf8)
        XCTAssertTrue(merged.contains("{\"id\":\"shared\"}"))
        XCTAssertTrue(merged.contains("{\"id\":\"account\"}"))
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: accountIndex.path),
            sharedIndex.path
        )
    }

    func testEnableRemovesLegacySharedSQLiteSymlink() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sharedState = root
            .appendingPathComponent(".shared-data", isDirectory: true)
            .appendingPathComponent("state_5.sqlite")
        let accountHome = root.appendingPathComponent("account", isDirectory: true)
        let accountState = accountHome.appendingPathComponent("state_5.sqlite")

        try FileManager.default.createDirectory(
            at: sharedState.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: accountHome, withIntermediateDirectories: true)
        try Data().write(to: sharedState)
        try FileManager.default.createSymbolicLink(at: accountState, withDestinationURL: sharedState)

        let account = Account(
            directoryName: "account",
            alias: "acct",
            email: nil,
            planType: nil,
            chatgptAccountId: nil,
            isActive: true,
            homeDirectory: accountHome,
            accessTokenExpired: false
        )

        try SharedCodexData(accountsBaseURL: root).enable(for: [account])

        XCTAssertTrue(FileManager.default.fileExists(atPath: accountState.path))
        XCTAssertThrowsError(try FileManager.default.destinationOfSymbolicLink(atPath: accountState.path))
    }

    func testEnableCompletesStaleStateBackfill() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let accountHome = root.appendingPathComponent("account", isDirectory: true)
        let stateDB = accountHome.appendingPathComponent("state_5.sqlite")
        try FileManager.default.createDirectory(at: accountHome, withIntermediateDirectories: true)
        try runSQLite(
            stateDB,
            sql: """
            create table backfill_state (
                id integer primary key check (id = 1),
                status text not null,
                last_watermark text,
                last_success_at integer,
                updated_at integer not null
            );
            insert into backfill_state values (1, 'running', 'sessions/old.jsonl', null, 1);
            """
        )

        let account = Account(
            directoryName: "account",
            alias: "acct",
            email: nil,
            planType: nil,
            chatgptAccountId: nil,
            isActive: true,
            homeDirectory: accountHome,
            accessTokenExpired: false
        )

        try SharedCodexData(accountsBaseURL: root).enable(for: [account])

        let output = try runSQLite(stateDB, sql: "select status, last_watermark from backfill_state where id = 1;")
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "complete|")
    }

    @discardableResult
    private func runSQLite(_ db: URL, sql: String) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        task.arguments = [db.path, sql]
        let output = Pipe()
        let error = Pipe()
        task.standardOutput = output
        task.standardError = error
        try task.run()
        task.waitUntilExit()
        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if task.terminationStatus != 0 {
            throw NSError(
                domain: "SharedCodexDataTests.sqlite",
                code: Int(task.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: stderr.isEmpty ? stdout : stderr]
            )
        }
        return stdout
    }
}
