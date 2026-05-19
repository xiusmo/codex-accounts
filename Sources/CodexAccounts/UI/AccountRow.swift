import SwiftUI

struct AccountRow: View {
    let account: Account
    let state: UsageState
    let hideEmail: Bool
    let showSparkUsage: Bool
    let showUsageResetTime: Bool
    let language: AppLanguage
    let onSwitch: () -> Void
    let onRemove: () -> Void

    @State private var confirmingRemove = false

    private var l10n: L10n { L10n(language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if confirmingRemove {
                removeConfirmRow
            } else {
                normalRow
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(rowBackground)
        )
    }

    private var rowBackground: Color {
        if confirmingRemove { return Color.secondary.opacity(0.06) }
        if account.isActive { return Color.secondary.opacity(0.055) }
        return Color.clear
    }

    private var normalRow: some View {
        HStack(alignment: .top, spacing: 6) {
            Button(action: onSwitch) {
                Image(systemName: account.isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(account.isActive ? Color.secondary.opacity(0.78) : Color.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(account.isActive)
            .help(account.isActive ? l10n.text(.activeAccountHelp) : l10n.text(.switchAccountHelp))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(account.commandAlias)
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(3)
                    planBadge
                    statusBadge
                    if account.isActive {
                        smallBadge(l10n.text(.current))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                contentForState
            }
            .layoutPriority(1)

            Button {
                confirmingRemove = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 16, height: 18)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(l10n.text(.removeAccountHelp))
        }
    }

    private var removeConfirmRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.format(.removeAccountFormat, displayName))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(l10n.text(.removeAccountDetail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button(l10n.text(.cancel)) { confirmingRemove = false }
                    .keyboardShortcut(.cancelAction)
                Button(l10n.text(.remove), role: .destructive) {
                    confirmingRemove = false
                    onRemove()
                }
                .foregroundStyle(.red)
            }
        }
    }

    private var displayPlan: String? {
        if let plan = account.planType { return plan }
        if case let .loaded(plan, _, _, _) = state, let plan { return plan }
        return nil
    }

    private var displayName: String {
        guard hideEmail else { return account.displayName }
        return EmailPrivacy.masked(account.email ?? account.displayName)
    }

    @ViewBuilder
    private var planBadge: some View {
        if let plan = displayPlan {
            smallBadge(plan)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch state {
        case .tokenExpired:
            smallBadge(l10n.text(.expired), foreground: .orange, background: Color.orange.opacity(0.10))
        case .authInvalid:
            smallBadge(l10n.text(.invalid), foreground: .orange, background: Color.orange.opacity(0.10))
        case .failed:
            smallBadge(l10n.text(.error), foreground: .secondary, background: Color.secondary.opacity(0.12))
        default:
            EmptyView()
        }
    }

    private func smallBadge(
        _ text: String,
        foreground: Color = .secondary,
        background: Color = Color.secondary.opacity(0.12)
    ) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(background)
            )
    }

    @ViewBuilder
    private var contentForState: some View {
        switch state {
        case .idle, .loading:
            VStack(spacing: 6) {
                UsageBar(title: "5h", snapshot: nil, showResetTime: showUsageResetTime, language: language)
                UsageBar(title: l10n.text(.week), snapshot: nil, showResetTime: showUsageResetTime, language: language)
            }
        case .loaded(_, let primary, let secondary, let additional):
            VStack(spacing: 6) {
                UsageBar(title: "5h", snapshot: primary, showResetTime: showUsageResetTime, language: language)
                UsageBar(title: l10n.text(.week), snapshot: secondary, showResetTime: showUsageResetTime, language: language)
                if showSparkUsage {
                    ForEach(Array(sparkLimits(from: additional).enumerated()), id: \.offset) { _, limit in
                        if limit.primary != nil {
                            UsageBar(title: "\(limit.displayName) 5h", snapshot: limit.primary, showResetTime: showUsageResetTime, language: language)
                        }
                        if limit.secondary != nil {
                            UsageBar(title: "\(limit.displayName) \(l10n.text(.week))", snapshot: limit.secondary, showResetTime: showUsageResetTime, language: language)
                        }
                    }
                }
            }
        case .tokenExpired(let raw):
            compactStatusLine(raw ?? l10n.text(.expired))
        case .authInvalid(let raw):
            compactStatusLine(raw ?? l10n.text(.invalid))
        case .noToken:
            compactStatusLine("tokens missing")
        case .failed(let msg):
            compactStatusLine(msg)
        }
    }

    private func compactStatusLine(_ text: String) -> some View {
        HStack(spacing: 0) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .truncationMode(.tail)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func sparkLimits(from additional: [AdditionalUsageSnapshot]) -> [AdditionalUsageSnapshot] {
        additional.filter { limit in
            limit.isSparkLimit && (limit.primary != nil || limit.secondary != nil)
        }
    }
}
