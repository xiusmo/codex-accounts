import Foundation

struct UsageBaselineSnapshot: Codable, Equatable {
    let remainingPercent: Double
    let capturedAt: Date
}

enum UsageBaselineMetricKey {
    static let primary = "default|primary"
    static let secondary = "default|secondary"

    static func additional(index: Int, limit: AdditionalUsageSnapshot, window: Window) -> String {
        let limitName = limit.limitName ?? ""
        let meteredFeature = limit.meteredFeature ?? ""
        return "additional|\(index)|\(limitName)|\(meteredFeature)|\(window.rawValue)"
    }

    static func snapshots(from state: UsageState) -> [(key: String, snapshot: WindowSnapshot)] {
        guard case let .loaded(_, primary, secondary, additional) = state else { return [] }
        var result: [(String, WindowSnapshot)] = []
        if let primary { result.append((Self.primary, primary)) }
        if let secondary { result.append((Self.secondary, secondary)) }
        for (index, limit) in additional.enumerated() {
            if let primary = limit.primary {
                result.append((Self.additional(index: index, limit: limit, window: .primary), primary))
            }
            if let secondary = limit.secondary {
                result.append((Self.additional(index: index, limit: limit, window: .secondary), secondary))
            }
        }
        return result
    }

    enum Window: String {
        case primary
        case secondary
    }
}

final class UsageBaselineStore {
    private struct Archive: Codable {
        var days: [String: [String: [String: UsageBaselineSnapshot]]] = [:]
    }

    private let defaults: UserDefaults
    private let key = "dailyUsageBaselines.v1"
    private let retentionDays = 8

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func today(now: Date = .now, calendar: Calendar = .current) -> [String: [String: UsageBaselineSnapshot]] {
        var archive = loadArchive()
        prune(&archive)
        saveArchive(archive)
        return archive.days[dayKey(for: now, calendar: calendar)] ?? [:]
    }

    func recordToday(
        accountKey: String,
        state: UsageState,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [String: [String: UsageBaselineSnapshot]] {
        var archive = loadArchive()
        prune(&archive)

        let todayKey = dayKey(for: now, calendar: calendar)
        var today = archive.days[todayKey] ?? [:]
        var account = today[accountKey] ?? [:]

        for metric in UsageBaselineMetricKey.snapshots(from: state) where account[metric.key] == nil {
            account[metric.key] = UsageBaselineSnapshot(
                remainingPercent: metric.snapshot.remainingPercent,
                capturedAt: now
            )
        }

        today[accountKey] = account
        archive.days[todayKey] = today
        prune(&archive)
        saveArchive(archive)
        return today
    }

    private func loadArchive() -> Archive {
        guard let data = defaults.data(forKey: key) else { return Archive() }
        return (try? JSONDecoder().decode(Archive.self, from: data)) ?? Archive()
    }

    private func saveArchive(_ archive: Archive) {
        guard let data = try? JSONEncoder().encode(archive) else { return }
        defaults.set(data, forKey: key)
    }

    private func prune(_ archive: inout Archive) {
        let keysToKeep = Set(archive.days.keys.sorted().suffix(retentionDays))
        archive.days = archive.days.filter { keysToKeep.contains($0.key) }
    }

    private func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
