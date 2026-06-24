import Foundation
import XCTest
@testable import CodexAccounts

final class UsageBaselineStoreTests: XCTestCase {
    @MainActor
    func testNextLocalMidnightRefreshDateUsesProvidedCalendarTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))

        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 6,
            day: 24,
            hour: 16,
            minute: 31,
            second: 0
        )))
        let expected = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 6,
            day: 25,
            hour: 0,
            minute: 1,
            second: 0
        )))

        XCTAssertEqual(
            AppState.nextLocalMidnightRefreshDate(after: now, calendar: calendar),
            expected
        )
    }

    func testHasBaselineTodayRequiresAllAccounts() {
        let suiteName = "UsageBaselineStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UsageBaselineStore(defaults: defaults)
        let loaded = UsageState.loaded(
            plan: nil,
            primary: nil,
            secondary: WindowSnapshot(usedPercent: 25, resetAt: nil, windowSeconds: nil),
            additional: []
        )

        _ = store.recordToday(accountKey: "one", state: loaded)

        XCTAssertTrue(store.hasBaselineToday(for: ["one"]))
        XCTAssertFalse(store.hasBaselineToday(for: ["one", "two"]))
    }
}
