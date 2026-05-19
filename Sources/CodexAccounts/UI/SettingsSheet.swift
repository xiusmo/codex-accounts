import SwiftUI

struct SettingsPane: View {
    @EnvironmentObject var state: AppState
    let onBack: () -> Void
    @State private var customRealPath: String = ""
    @State private var showCustomPath = false
    @State private var aliasDrafts: [String: String] = [:]
    @State private var aliasesExpanded = false

    private var l10n: L10n { L10n(language: state.appLanguage) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            state.refreshShimStatus()
            state.refreshLaunchAtLoginStatus()
            syncAliasDrafts()
        }
        .onChange(of: state.accounts) { _ in
            syncAliasDrafts()
        }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            Spacer()
            Text(l10n.text(.settings)).font(.system(size: 13, weight: .semibold))
            Spacer()
            Color.clear.frame(width: 12, height: 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsSection(l10n.text(.preferences)) {
                privacyBlock
            }

            Divider()

            aliasSection

            if let error = state.generalError {
                settingsErrorBlock(error)
            }

            Divider()

            settingsSection(l10n.text(.codexCommand)) {
                if let status = state.shimStatus {
                    shimBlock(status)
                } else {
                    Text("…").font(.caption).foregroundStyle(.secondary)
                }
            }

            Divider()

            quitRow
        }
    }

    private var aliasBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            if state.accounts.isEmpty {
                Text(l10n.text(.noAccounts))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.accounts) { account in
                    aliasRow(account)
                }
                Text(l10n.format(.commandExampleFormat, state.accounts.first?.alias ?? "ash"))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var aliasSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    aliasesExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(l10n.text(.accountAliases))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(aliasSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Image(systemName: aliasesExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if aliasesExpanded {
                aliasBlock
                    .transition(.opacity)
            }
        }
    }

    private var aliasSummary: String {
        state.accounts.isEmpty ? l10n.text(.noAccounts) : l10n.format(.accountCountFormat, state.accounts.count)
    }

    private func aliasRow(_ account: Account) -> some View {
        let draft = Binding<String>(
            get: { aliasDrafts[account.directoryName] ?? account.alias },
            set: { aliasDrafts[account.directoryName] = $0 }
        )
        let currentDraft = aliasDrafts[account.directoryName] ?? account.alias
        let changed = currentDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != account.alias

        return HStack(alignment: .center, spacing: 8) {
            Text(displayName(for: account))
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("ash", text: draft)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
                .frame(width: 84)
                .onSubmit { saveAlias(account) }

            Button(l10n.text(.save)) {
                saveAlias(account)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!changed)
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var privacyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            languageRow

            settingToggle(
                title: l10n.text(.hideAccountEmail),
                isOn: Binding(
                    get: { state.hideAccountEmail },
                    set: { state.setHideAccountEmail($0) }
                )
            )
            .help(l10n.text(.hideAccountEmailHelp))

            settingToggle(
                title: l10n.text(.showSparkUsage),
                isOn: Binding(
                    get: { state.showSparkUsage },
                    set: { state.setShowSparkUsage($0) }
                )
            )
            .help(l10n.text(.showSparkUsageHelp))

            settingToggle(
                title: l10n.text(.showUsageResetTime),
                detail: l10n.text(.showUsageResetTimeDetail),
                isOn: Binding(
                    get: { state.showUsageResetTime },
                    set: { state.setShowUsageResetTime($0) }
                )
            )
            .help(l10n.text(.showUsageResetTimeHelp))

            settingToggle(
                title: l10n.text(.showDailyUsageBaseline),
                detail: l10n.text(.showDailyUsageBaselineDetail),
                isOn: Binding(
                    get: { state.showDailyUsageBaseline },
                    set: { state.setShowDailyUsageBaseline($0) }
                )
            )
            .help(l10n.text(.showDailyUsageBaselineHelp))

            settingToggle(
                title: l10n.text(.shareCodexData),
                detail: l10n.text(.shareCodexDataDetail),
                isOn: Binding(
                    get: { state.shareCodexData },
                    set: { state.setShareCodexData($0) }
                ),
                isDisabled: state.shareCodexDataBusy
            )
            .help(l10n.text(.shareCodexDataHelp))

            settingToggle(
                title: l10n.text(.shareCodexConfig),
                detail: l10n.text(.shareCodexConfigDetail),
                isOn: Binding(
                    get: { state.shareCodexConfig },
                    set: { state.setShareCodexConfig($0) }
                ),
                isDisabled: state.shareCodexConfigBusy
            )
            .help(l10n.text(.shareCodexConfigHelp))

            settingToggle(
                title: l10n.text(.launchAtLogin),
                isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                )
            )
            .help(l10n.text(.launchAtLoginHelp))
        }
    }

    private var languageRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(l10n.text(.language))
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Menu {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        state.setAppLanguage(language)
                    } label: {
                        if language == state.appLanguage {
                            Label(language.displayName(in: state.appLanguage), systemImage: "checkmark")
                        } else {
                            Text(language.displayName(in: state.appLanguage))
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text(state.appLanguage.displayName(in: state.appLanguage))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 118)
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func settingToggle(
        title: String,
        detail: String? = nil,
        isOn: Binding<Bool>,
        isDisabled: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(isDisabled)
        }
    }

    private func displayName(for account: Account) -> String {
        guard state.hideAccountEmail else { return account.displayName }
        return EmailPrivacy.masked(account.email ?? account.displayName)
    }

    private func saveAlias(_ account: Account) {
        let value = aliasDrafts[account.directoryName] ?? account.alias
        state.setAlias(value, for: account)
    }

    private func syncAliasDrafts() {
        var next = aliasDrafts
        let validKeys = Set(state.accounts.map(\.directoryName))
        next = next.filter { validKeys.contains($0.key) }
        for account in state.accounts where next[account.directoryName] == nil {
            next[account.directoryName] = account.alias
        }
        aliasDrafts = next
    }

    @ViewBuilder
    private func shimBlock(_ status: ShimInstaller.Status) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l10n.text(.status))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                statusLabel(status)
            }

            if let real = status.detectedRealCodex {
                VStack(alignment: .leading, spacing: 5) {
                    pathRow(label: l10n.text(.entry), value: status.installPath)
                    pathRow(label: l10n.text(.real), value: real)
                }
            } else {
                Text(l10n.text(.codexNotDetected))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if case .ours = status.installed, !status.pathPrecedenceOK {
                pathHint
            }

            if let error = state.shimError {
                shimErrorBlock(error)
            }

            HStack(spacing: 8) {
                Button(installLabel(status)) {
                    let real = customRealPath.isEmpty ? (status.detectedRealCodex ?? "") : customRealPath
                    guard !real.isEmpty else { return }
                    state.installShim(realCodex: real)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled((status.detectedRealCodex ?? "").isEmpty && customRealPath.isEmpty)

                if status.installed != .missing {
                    Button(l10n.text(.uninstall)) { state.uninstallShim() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Spacer()

                Button(showCustomPath ? l10n.text(.collapse) : l10n.text(.customPath)) {
                    showCustomPath.toggle()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if showCustomPath {
                TextField("/opt/homebrew/bin/codex", text: $customRealPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
            }
        }
    }

    private func statusLabel(_ status: ShimInstaller.Status) -> some View {
        let (text, color): (String, Color) = {
            switch status.installed {
            case .missing: return (l10n.text(.shimMissing), .secondary)
            case .ours: return (l10n.text(.shimManaged), .green)
            case .foreign: return (l10n.text(.shimUnmanaged), .secondary)
            }
        }()
        return Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
    }

    private func installLabel(_ status: ShimInstaller.Status) -> String {
        if status.shimNeedsUpdate { return l10n.text(.update) }
        switch status.installed {
            case .missing: return l10n.text(.install)
            case .ours: return l10n.text(.reinstall)
            case .foreign: return l10n.text(.takeover)
        }
    }

    private func pathRow(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private var pathHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
            Text(l10n.text(.terminalBypassesTakeover))
                .font(.caption)
                .foregroundStyle(.orange)
            Spacer()
        }
    }

    private func shimErrorBlock(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l10n.text(.autoTakeoverFailed))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(6)
                .textSelection(.enabled)
                .padding(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.10))
                )
        }
    }

    private func settingsErrorBlock(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(message)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .textSelection(.enabled)
            Spacer()
            Button {
                state.generalError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
        )
    }

    private var quitRow: some View {
        HStack {
            Spacer()
            Button(l10n.text(.quitApp)) { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q", modifiers: [.command])
        }
    }
}
