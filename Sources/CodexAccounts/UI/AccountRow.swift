import SwiftUI

struct AccountRow: View {
    let account: Account
    let state: UsageState
    let hideEmail: Bool
    let onSwitch: () -> Void
    let onRemove: () -> Void

    @State private var confirmingRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if confirmingRemove {
                removeConfirmRow
            } else {
                normalRow
                contentForState
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
        HStack(alignment: .center, spacing: 10) {
            Button(action: onSwitch) {
                Image(systemName: account.isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(account.isActive ? Color.secondary.opacity(0.78) : Color.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(account.isActive)
            .help(account.isActive ? "当前活跃账户" : "切换到此账户")

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                planBadge
                statusBadge
                if account.isActive {
                    smallBadge("当前")
                }
            }

            Spacer()

            Button {
                confirmingRemove = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("移除账户")
        }
    }

    private var removeConfirmRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("移除 \(displayName)?")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("退出登录并删除本地数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("取消") { confirmingRemove = false }
                    .keyboardShortcut(.cancelAction)
                Button("移除", role: .destructive) {
                    confirmingRemove = false
                    onRemove()
                }
                .foregroundStyle(.red)
            }
        }
    }

    private var displayPlan: String? {
        if let plan = account.planType { return plan }
        if case let .loaded(plan, _, _) = state, let plan { return plan }
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
            smallBadge("过期", foreground: .orange, background: Color.orange.opacity(0.10))
        case .authInvalid:
            smallBadge("失效", foreground: .orange, background: Color.orange.opacity(0.10))
        case .failed:
            smallBadge("错误", foreground: .secondary, background: Color.secondary.opacity(0.12))
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
                UsageBar(title: "5h", snapshot: nil)
                UsageBar(title: "week", snapshot: nil)
            }
            .padding(.leading, 28)
        case .loaded(_, let primary, let secondary):
            VStack(spacing: 6) {
                UsageBar(title: "5h", snapshot: primary)
                UsageBar(title: "week", snapshot: secondary)
            }
            .padding(.leading, 28)
        case .tokenExpired(let raw):
            compactStatusLine(raw ?? "过期")
        case .authInvalid(let raw):
            compactStatusLine(raw ?? "失效")
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
        .padding(.leading, 28)
    }
}
