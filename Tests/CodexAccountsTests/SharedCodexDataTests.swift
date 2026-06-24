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

        XCTAssertFalse(FileManager.default.fileExists(atPath: accountState.path))
        XCTAssertThrowsError(try FileManager.default.destinationOfSymbolicLink(atPath: accountState.path))
    }
}
