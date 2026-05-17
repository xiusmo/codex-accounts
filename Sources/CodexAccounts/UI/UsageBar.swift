import SwiftUI

struct UsageBar: View {
    let title: String
    let snapshot: WindowSnapshot?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: titleWidth, alignment: .leading)
                BarView(percent: snapshot?.remainingPercent ?? 0)
                    .frame(height: 5)
                Text(metaLabel(now: context.date))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 90, alignment: .trailing)
            }
        }
    }

    private func metaLabel(now: Date) -> String {
        guard let snapshot else { return "--%" }
        let percent = "\(Int(snapshot.remainingPercent.rounded()))%"
        guard let reset = snapshot.resetAt else { return percent }
        return "\(percent) · \(formatTimeUntil(reset, now: now))"
    }

    private var titleWidth: CGFloat {
        title.count > 4 ? 82 : 36
    }
}

private struct BarView: View {
    let percent: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.18))
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: max(2, geo.size.width * clamped))
            }
        }
    }

    private var clamped: Double { max(0, min(1, percent / 100)) }
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
