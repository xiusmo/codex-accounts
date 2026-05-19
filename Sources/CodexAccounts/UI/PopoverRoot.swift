import SwiftUI
import AppKit

struct PopoverRoot: View {
    @EnvironmentObject var state: AppState
    @State private var showingSettings = false

    private var l10n: L10n { L10n(language: state.appLanguage) }

    var body: some View {
        Group {
            if showingSettings {
                SettingsPane(onBack: { showingSettings = false })
            } else {
                accountsView
            }
        }
        .id(showingSettings ? "settings" : "accounts")
        .frame(width: panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            Task { await state.refreshAllUsageIfStale() }
        }
    }

    private var panelWidth: CGFloat {
        Layout.panelWidth(
            accounts: state.accounts,
            importCandidates: state.codexImportCandidates,
            hideEmail: state.hideAccountEmail,
            showingSettings: showingSettings
        )
    }

    private var accountsView: some View {
        VStack(spacing: 0) {
            header
            if hasContentRegion {
                Divider()
                AdaptiveHeightScrollView(
                    minHeight: contentRegionMinimumHeight,
                    maxHeight: contentRegionMaxHeight,
                    fallbackHeight: contentRegionFallbackHeight
                ) {
                    content.padding(.vertical, 8)
                }
            }
            if state.pendingSwitch != nil {
                Divider()
                pendingSwitchBanner
            }
            Divider()
            footer
        }
    }

    private var hasContentRegion: Bool {
        !state.codexImportCandidates.isEmpty || !state.accounts.isEmpty || state.generalError != nil || state.loginError != nil
    }

    private var contentRegionMinimumHeight: CGFloat {
        if !state.accounts.isEmpty { return Layout.minAccountRegionHeight }
        if !state.codexImportCandidates.isEmpty { return Layout.minImportRegionHeight }
        return Layout.minMessageRegionHeight
    }

    private var contentRegionMaxHeight: CGFloat {
        Layout.maxContentRegionHeight(hasPendingBanner: state.pendingSwitch != nil)
    }

    private var contentRegionFallbackHeight: CGFloat {
        let importHeight = CGFloat(state.codexImportCandidates.count) * Layout.estimatedImportRowHeight
        let accountHeight = CGFloat(state.accounts.count) * Layout.estimatedAccountRowHeight
        let messageCount = [state.generalError, state.loginError].compactMap { $0 }.count
        let messageHeight = CGFloat(messageCount) * Layout.estimatedMessageHeight
        return min(
            contentRegionMaxHeight,
            max(contentRegionMinimumHeight, importHeight + accountHeight + messageHeight + Layout.contentVerticalPadding * 2)
        )
    }

    private var pendingSwitchBanner: some View {
        VStack(alignment: .leading, spacing: 7) {
            if state.confirmingTerminateRunningCodex {
                terminateConfirmRow
            } else {
                pendingSwitchRow
            }
            Text(state.confirmingTerminateRunningCodex
                 ? l10n.text(.pendingSwitchAfterTerminate)
                 : l10n.text(.pendingSwitchKeepsRunning))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var pendingSwitchRow: some View {
        HStack(alignment: .center, spacing: 7) {
            Text(l10n.text(.codexRunning))
                .font(.system(size: 12, weight: .semibold))
            processCountBadge
            Spacer()
            Button(l10n.text(.cancel)) {
                state.cancelPendingSwitch()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button(l10n.text(.lazyTerminate)) {
                state.requestTerminateRunningCodex()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button(l10n.text(.switch)) {
                state.confirmPendingSwitch()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var terminateConfirmRow: some View {
        HStack(alignment: .center, spacing: 7) {
            Text(l10n.text(.terminateCodexPrompt))
                .font(.system(size: 12, weight: .semibold))
            processCountBadge
            Spacer()
            Button(l10n.text(.back)) {
                state.cancelTerminateRunningCodex()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button(l10n.text(.terminateAndSwitch)) {
                state.confirmTerminateRunningCodexAndSwitch()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundStyle(.red)
        }
    }

    private var processCountBadge: some View {
        Text(l10n.format(.processCountFormat, state.runningCodexHits.count))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.10))
            )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Codex Accounts")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if let label = refreshTimestampLabel {
                Text(label)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(refreshTimestampHelp)
            }
            Button {
                Task { await state.refreshAllUsage() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .opacity(state.usageRefreshInProgress ? 0 : 1)
                    .overlay {
                        if state.usageRefreshInProgress {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.55)
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(state.usageRefreshInProgress)
            .help(state.usageRefreshInProgress ? l10n.text(.refreshingUsage) : l10n.text(.refreshUsageHelp))

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help(l10n.text(.settingsHelp))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var refreshTimestampLabel: String? {
        if state.usageRefreshInProgress { return l10n.text(.updateInProgress) }
        guard let date = state.lastSuccessfulUsageRefreshAt else { return nil }
        let formatter = DateFormatter()
        formatter.locale = state.appLanguage.locale
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M/d HH:mm"
        return l10n.format(.updatedAtFormat, formatter.string(from: date))
    }

    private var refreshTimestampHelp: String {
        if state.usageRefreshInProgress { return l10n.text(.refreshingUsage) }
        guard let date = state.lastSuccessfulUsageRefreshAt else { return l10n.text(.noSuccessfulRefresh) }
        let formatter = DateFormatter()
        formatter.locale = state.appLanguage.locale
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return l10n.format(.lastSuccessfulRefreshFormat, formatter.string(from: date))
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 8) {
            if !state.codexImportCandidates.isEmpty {
                VStack(spacing: 4) {
                    ForEach(state.codexImportCandidates) { candidate in
                        importCandidateRow(candidate)
                            .padding(.horizontal, 12)
                    }
                }
            }

            if !state.accounts.isEmpty {
                VStack(spacing: 4) {
                    ForEach(sortedAccounts) { account in
                        AccountRow(
                            account: account,
                            state: state.usage[account.directoryName] ?? .idle,
                            hideEmail: state.hideAccountEmail,
                            showSparkUsage: state.showSparkUsage,
                            showUsageResetTime: state.showUsageResetTime,
                            showDailyUsageBaseline: state.showDailyUsageBaseline,
                            dailyUsageBaselines: state.dailyUsageBaselines[account.directoryName] ?? [:],
                            language: state.appLanguage,
                            onSwitch: { state.requestSwitch(to: account) },
                            onRemove: { state.removeAccount(account) }
                        )
                        .padding(.horizontal, 6)
                    }
                }
                .animation(Layout.accountMoveAnimation, value: sortedAccountOrderKey)
            }

            if let err = state.generalError {
                errorBlock(message: err, onDismiss: { state.generalError = nil })
            }
            if let loginErr = state.loginError {
                errorBlock(message: loginErr, onDismiss: { state.loginError = nil })
            }
        }
    }

    private func importCandidateRow(_ candidate: CodexImportCandidate) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(displayName(for: candidate))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let plan = candidate.planType {
                        Text(plan)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.secondary.opacity(0.12))
                            )
                    }
                }
                Text(l10n.format(.existingCodexLoginFormat, candidate.sourceLabel))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(l10n.text(.takeover)) {
                state.takeoverCodexAccount(candidate)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func errorBlock(message: String, onDismiss: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(l10n.text(.close))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            Button {
                if state.loginInProgress {
                    state.cancelAddAccount()
                } else {
                    state.startAddAccount()
                }
            } label: {
                HStack(spacing: 4) {
                    if state.loginInProgress {
                        ProgressView().controlSize(.small)
                        Text(l10n.text(.cancelLogin))
                    } else {
                        Image(systemName: "plus")
                        Text(l10n.text(.addAccount))
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(state.loginInProgress ? l10n.text(.cancelLoginHelp) : l10n.text(.addAccountHelp))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func displayName(for candidate: CodexImportCandidate) -> String {
        guard state.hideAccountEmail else { return candidate.displayName }
        return EmailPrivacy.masked(candidate.email ?? candidate.displayName)
    }

    private var sortedAccounts: [Account] {
        state.accounts.enumerated().sorted { lhs, rhs in
            let left = lhs.element
            let right = rhs.element

            if left.isActive != right.isActive {
                return left.isActive
            }

            let leftScore = usageSortScore(for: left)
            let rightScore = usageSortScore(for: right)
            if leftScore.effectiveRemaining != rightScore.effectiveRemaining {
                return leftScore.effectiveRemaining > rightScore.effectiveRemaining
            }
            if leftScore.averageRemaining != rightScore.averageRemaining {
                return leftScore.averageRemaining > rightScore.averageRemaining
            }
            if leftScore.primaryRemaining != rightScore.primaryRemaining {
                return leftScore.primaryRemaining > rightScore.primaryRemaining
            }
            if leftScore.secondaryRemaining != rightScore.secondaryRemaining {
                return leftScore.secondaryRemaining > rightScore.secondaryRemaining
            }

            return lhs.offset < rhs.offset
        }
        .map(\.element)
    }

    private var sortedAccountOrderKey: String {
        sortedAccounts.map(\.directoryName).joined(separator: "|")
    }

    private func usageSortScore(for account: Account) -> AccountUsageSortScore {
        guard case let .loaded(_, primary, secondary, additional) = state.usage[account.directoryName] else {
            return .unknown
        }

        let primaryRemaining = remainingPercent(primary)
        let secondaryRemaining = remainingPercent(secondary)
        let sparkRemaining = state.showSparkUsage
            ? additional
                .filter { $0.isSparkLimit }
                .flatMap { [remainingPercent($0.primary), remainingPercent($0.secondary)] }
            : []
        let known = ([primaryRemaining, secondaryRemaining] + sparkRemaining).compactMap { $0 }
        guard !known.isEmpty else {
            return .unknown
        }

        return AccountUsageSortScore(
            effectiveRemaining: known.min() ?? 0,
            averageRemaining: known.reduce(0, +) / Double(known.count),
            primaryRemaining: primaryRemaining ?? -1,
            secondaryRemaining: secondaryRemaining ?? -1
        )
    }

    private func remainingPercent(_ snapshot: WindowSnapshot?) -> Double? {
        guard let snapshot else { return nil }
        return snapshot.remainingPercent
    }
}

private struct AccountUsageSortScore {
    let effectiveRemaining: Double
    let averageRemaining: Double
    let primaryRemaining: Double
    let secondaryRemaining: Double

    static let unknown = AccountUsageSortScore(
        effectiveRemaining: -1,
        averageRemaining: -1,
        primaryRemaining: -1,
        secondaryRemaining: -1
    )
}

private enum Layout {
    static let accountMoveAnimation = Animation.spring(response: 0.34, dampingFraction: 0.84, blendDuration: 0.06)
    static let minimumPanelWidth: CGFloat = 420
    static let maximumPanelWidth: CGFloat = 540
    static let minAccountRegionHeight: CGFloat = 78
    static let minImportRegionHeight: CGFloat = 58
    static let minMessageRegionHeight: CGFloat = 44
    static let estimatedAccountRowHeight: CGFloat = 92
    static let estimatedImportRowHeight: CGFloat = 60
    static let estimatedMessageHeight: CGFloat = 48
    static let contentVerticalPadding: CGFloat = 8
    static let maximumTallScreenContentHeight: CGFloat = 820

    static func panelWidth(
        accounts: [Account],
        importCandidates: [CodexImportCandidate],
        hideEmail: Bool,
        showingSettings: Bool
    ) -> CGFloat {
        let visibleWidth = currentScreenVisibleWidth()
        let screenMax = min(maximumPanelWidth, max(320, visibleWidth - 64))
        let screenMin = min(minimumPanelWidth, screenMax)
        let longestAccount = accounts
            .map { accountHeaderLength($0, hideEmail: hideEmail) }
            .max() ?? 0
        let longestImport = importCandidates
            .map { candidateDisplayName($0, hideEmail: hideEmail).count }
            .max() ?? 0
        let longest = max(longestAccount, longestImport)
        let contentBased = 282 + CGFloat(longest) * 6.6
        let target = showingSettings ? max(460, contentBased) : max(minimumPanelWidth, contentBased)
        return max(screenMin, min(screenMax, target.rounded(.up)))
    }

    static func maxContentRegionHeight(hasPendingBanner: Bool) -> CGFloat {
        let visibleHeight = currentScreenVisibleHeight()
        let reservedChrome: CGFloat = hasPendingBanner ? 190 : 112
        let screenBasedHeight = visibleHeight * 0.88 - reservedChrome
        return min(
            maximumTallScreenContentHeight,
            max(420, screenBasedHeight.rounded(.down))
        )
    }

    private static func accountHeaderLength(_ account: Account, hideEmail: Bool) -> Int {
        let display = hideEmail
            ? EmailPrivacy.masked(account.email ?? account.displayName)
            : account.displayName
        let planLength = (account.planType ?? "").count
        let activeLength = account.isActive ? 2 : 0
        return account.commandAlias.count + display.count + planLength + activeLength
    }

    private static func candidateDisplayName(_ candidate: CodexImportCandidate, hideEmail: Bool) -> String {
        guard hideEmail else { return candidate.displayName }
        return EmailPrivacy.masked(candidate.email ?? candidate.displayName)
    }

    private static func currentScreenVisibleHeight() -> CGFloat {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { screen in
            NSMouseInRect(mouse, screen.frame, false)
        } ?? NSScreen.main
        return screen?.visibleFrame.height ?? 800
    }

    private static func currentScreenVisibleWidth() -> CGFloat {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { screen in
            NSMouseInRect(mouse, screen.frame, false)
        } ?? NSScreen.main
        return screen?.visibleFrame.width ?? 900
    }
}

private struct AdaptiveHeightScrollView<Content: View>: View {
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let fallbackHeight: CGFloat
    @ViewBuilder let content: () -> Content

    @State private var measuredHeight: CGFloat = 0

    private var resolvedHeight: CGFloat {
        let naturalHeight = measuredHeight > 1 ? measuredHeight : fallbackHeight
        return min(max(naturalHeight, minHeight), maxHeight)
    }

    var body: some View {
        ScrollView {
            content()
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ContentHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                )
        }
        .frame(height: resolvedHeight)
        .animation(.easeInOut(duration: 0.16), value: resolvedHeight)
        .onPreferenceChange(ContentHeightPreferenceKey.self) { height in
            guard abs(measuredHeight - height) > 0.5 else { return }
            measuredHeight = height
        }
    }
}

private struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
