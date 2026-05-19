import SwiftUI

struct UsageBar: View {
    let title: String
    let snapshot: WindowSnapshot?
    let baseline: UsageBaselineSnapshot?
    let showResetTime: Bool
    let language: AppLanguage

    private var l10n: L10n { L10n(language: language) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: UsageBarLayout.columnSpacing) {
                Text(title)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: UsageBarLayout.titleWidth, alignment: .leading)
                BarView(
                    percent: snapshot?.remainingPercent ?? 0,
                    baselinePercent: baselinePercent
                )
                    .frame(height: 5)
                    .help(baselineHelp)
                UsageMetaView(
                    snapshot: snapshot,
                    now: context.date,
                    showResetTime: showResetTime,
                    language: language
                )
            }
        }
    }

    private var baselinePercent: Double? {
        guard snapshot != nil else { return nil }
        return baseline?.remainingPercent
    }

    private var baselineHelp: String {
        guard let snapshot, let baseline else { return "" }
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

    var body: some View {
        HStack(spacing: 4) {
            Text(percentText)
                .frame(width: UsageBarLayout.percentWidth, alignment: .trailing)
            if snapshot?.resetAt != nil {
                Text("·")
                Text(relativeText)
                    .frame(width: UsageBarLayout.relativeWidth, alignment: .leading)
                if showResetTime {
                    Text("·")
                    Text(resetText)
                        .frame(width: UsageBarLayout.resetWidth, alignment: .leading)
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
        showResetTime ? UsageBarLayout.resetMetaWidth : UsageBarLayout.compactMetaWidth
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

private enum UsageBarLayout {
    static let titleWidth: CGFloat = 78
    static let columnSpacing: CGFloat = 5
    static let percentWidth: CGFloat = 38
    static let relativeWidth: CGFloat = 50
    static let resetWidth: CGFloat = 66
    static let compactMetaWidth: CGFloat = 100
    static let resetMetaWidth: CGFloat = 174
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
