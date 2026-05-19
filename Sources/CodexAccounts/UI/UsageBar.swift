import SwiftUI

struct UsageMetricRow: Identifiable {
    let id: String
    let title: String
    let snapshot: WindowSnapshot?
    let baseline: UsageBaselineSnapshot?
}

struct UsageRows: View {
    let rows: [UsageMetricRow]
    let showResetTime: Bool
    let language: AppLanguage

    private let rowHeight: CGFloat = 16
    private let rowSpacing: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let layout = UsageBarLayout.resolved(
                    containerWidth: proxy.size.width,
                    showsExtendedTitles: rows.contains { $0.title.count > 5 },
                    showResetTime: showResetTime
                )

                VStack(spacing: rowSpacing) {
                    ForEach(rows) { row in
                        UsageBar(
                            row: row,
                            now: context.date,
                            layout: layout,
                            showResetTime: showResetTime,
                            language: language
                        )
                        .frame(height: rowHeight)
                    }
                }
            }
        }
        .frame(height: rowsHeight)
    }

    private var rowsHeight: CGFloat {
        guard !rows.isEmpty else { return 0 }
        return CGFloat(rows.count) * rowHeight + CGFloat(rows.count - 1) * rowSpacing
    }
}

private struct UsageBar: View {
    let row: UsageMetricRow
    let now: Date
    let layout: UsageBarLayout
    let showResetTime: Bool
    let language: AppLanguage

    private var l10n: L10n { L10n(language: language) }

    var body: some View {
        HStack(spacing: layout.columnSpacing) {
            Text(row.title)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: layout.titleWidth, alignment: .leading)
            BarView(
                percent: row.snapshot?.remainingPercent ?? 0,
                baselinePercent: baselinePercent
            )
            .frame(width: layout.barWidth, height: 5)
            .help(baselineHelp)
            UsageMetaView(
                snapshot: row.snapshot,
                now: now,
                showResetTime: showResetTime,
                language: language,
                layout: layout
            )
        }
        .frame(width: layout.totalWidth(showResetTime: showResetTime), alignment: .leading)
    }

    private var baselinePercent: Double? {
        guard row.snapshot != nil else { return nil }
        return row.baseline?.remainingPercent
    }

    private var baselineHelp: String {
        guard let snapshot = row.snapshot, let baseline = row.baseline else { return "" }
        let usedToday = max(0, baseline.remainingPercent - snapshot.remainingPercent)
        return l10n.format(
            .dailyUsageBaselineHelpFormat,
            formatPercent(usedToday),
            formatPercent(baseline.remainingPercent)
        )
    }
}

private struct UsageMetaView: View {
    let snapshot: WindowSnapshot?
    let now: Date
    let showResetTime: Bool
    let language: AppLanguage
    let layout: UsageBarLayout

    var body: some View {
        HStack(spacing: layout.metaSpacing) {
            Text(percentText)
                .frame(width: layout.percentWidth, alignment: .trailing)
            if snapshot?.resetAt != nil {
                Text(relativeText)
                    .frame(width: layout.relativeWidth, alignment: .leading)
                if showResetTime {
                    Text(resetText)
                        .frame(width: layout.resetWidth, alignment: .leading)
                }
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .frame(width: metaWidth, alignment: .leading)
    }

    private var percentText: String {
        guard let snapshot else { return "--%" }
        return "\(Int(snapshot.remainingPercent.rounded()))%"
    }

    private var relativeText: String {
        guard let reset = snapshot?.resetAt else { return "" }
        return formatTimeUntil(reset, now: now)
    }

    private var resetText: String {
        guard let reset = snapshot?.resetAt else { return "" }
        return formatResetTime(reset, now: now, language: language)
    }

    private var metaWidth: CGFloat {
        showResetTime ? layout.resetMetaWidth : layout.compactMetaWidth
    }
}

private struct BarView: View {
    let percent: Double
    let baselinePercent: Double?

    var body: some View {
        GeometryReader { geo in
            barTrack(width: geo.size.width)
                .overlay(alignment: .leading) {
                    if let baselinePercent {
                        BaselineMarker(trackHeight: geo.size.height)
                            .position(
                                x: markerCenterX(width: geo.size.width, percent: baselinePercent),
                                y: geo.size.height / 2
                            )
                    }
                }
        }
    }

    private var clamped: Double { max(0, min(1, percent / 100)) }

    private func barTrack(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.secondary.opacity(0.18))
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.secondary.opacity(0.45))
                .frame(width: max(2, width * clamped))
        }
    }

    private func markerCenterX(width: CGFloat, percent: Double) -> CGFloat {
        guard width > 1 else { return width / 2 }
        let clampedPercent = max(0, min(1, percent / 100))
        return max(0.75, min(width - 0.75, width * clampedPercent))
    }
}

private struct BaselineMarker: View {
    let trackHeight: CGFloat

    var body: some View {
        Capsule(style: .continuous)
            .fill(Color.primary.opacity(0.64))
            .frame(width: 1.5, height: max(trackHeight + 3, 7))
            .shadow(color: Color.black.opacity(0.16), radius: 0.5, x: 0, y: 0.5)
        .accessibilityHidden(true)
    }
}

private func formatPercent(_ value: Double) -> String {
    "\(Int(value.rounded()))%"
}

struct UsageBarLayout {
    let titleWidth: CGFloat
    let barWidth: CGFloat
    let columnSpacing: CGFloat = 5
    let metaSpacing: CGFloat = 8
    let percentWidth: CGFloat = 38
    let relativeWidth: CGFloat = 50
    let resetWidth: CGFloat = 66

    var compactMetaWidth: CGFloat {
        percentWidth + metaSpacing + relativeWidth
    }

    var resetMetaWidth: CGFloat {
        percentWidth + metaSpacing + relativeWidth + metaSpacing + resetWidth
    }

    func totalWidth(showResetTime: Bool) -> CGFloat {
        titleWidth + columnSpacing + barWidth + columnSpacing + (showResetTime ? resetMetaWidth : compactMetaWidth)
    }

    static func resolved(
        containerWidth: CGFloat,
        showsExtendedTitles: Bool,
        showResetTime: Bool
    ) -> UsageBarLayout {
        let titleWidth: CGFloat = showsExtendedTitles ? 78 : 36
        let reference = UsageBarLayout(titleWidth: titleWidth, barWidth: 0)
        let metaWidth = showResetTime ? reference.resetMetaWidth : reference.compactMetaWidth
        let spacings: CGFloat = 10
        let minimumBarWidth: CGFloat = showsExtendedTitles ? 150 : 190
        let availableBarWidth = containerWidth - titleWidth - metaWidth - spacings
        return UsageBarLayout(
            titleWidth: titleWidth,
            barWidth: max(minimumBarWidth, availableBarWidth.rounded(.down))
        )
    }
}

func formatTimeUntil(_ date: Date, now: Date = .now) -> String {
    let seconds = Int(max(0, date.timeIntervalSince(now)))
    let days = seconds / 86_400
    let hours = (seconds % 86_400) / 3_600
    let minutes = (seconds % 3_600) / 60
    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(String(format: "%02d", minutes))m" }
    return "\(minutes)m"
}

func formatResetTime(_ date: Date, now: Date = .now, language: AppLanguage = .current) -> String {
    let calendar = Calendar.current
    let formatter = DateFormatter()
    formatter.locale = language.locale

    if calendar.isDateInToday(date) {
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    if calendar.isDateInTomorrow(date) {
        formatter.dateFormat = "HH:mm"
        return L10n.format(.tomorrowFormat, formatter.string(from: date), language: language)
    }

    formatter.dateFormat = "M/d HH:mm"
    return formatter.string(from: date)
}
