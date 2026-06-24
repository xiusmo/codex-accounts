import XCTest
@testable import CodexAccounts

final class ShimInstallerTests: XCTestCase {
    func testPathEntriesExpandHome() {
        XCTAssertEqual(
            ShimInstaller.pathEntries(from: "~/bin:/usr/bin:~", home: "/Users/example"),
            ["/Users/example/bin", "/usr/bin", "/Users/example"]
        )
    }

    func testJoinedUniquePathPreservesFirstPrecedence() {
        XCTAssertEqual(
            ShimInstaller.joinedUniquePATH(
                [
                    "/first:/shared",
                    "/second:/shared:/third"
                ],
                home: "/Users/example"
            ),
            "/first:/shared:/second:/third"
        )
    }

    func testExtractPathIgnoresShellStartupOutput() {
        XCTAssertEqual(
            ShimInstaller.extractPATH(
                from: "banner\n__CODEX_ACCOUNTS_PATH_BEGIN__/first:/second__CODEX_ACCOUNTS_PATH_END__\nfooter"
            ),
            "/first:/second"
        )
    }
}
