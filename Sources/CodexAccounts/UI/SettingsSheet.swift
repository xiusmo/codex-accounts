import SwiftUI

struct SettingsPane: View {
    @EnvironmentObject var state: AppState
    let onBack: () -> Void
    @State private var customRealPath: String = ""
    @State private var showCustomPath = false
    @State private var aliasDrafts: [String: String] = [:]
    @State private var aliasesExpanded = false

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
            Text("设置").font(.system(size: 13, weight: .semibold))
            Spacer()
            Color.clear.frame(width: 12, height: 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsSection("偏好") {
                privacyBlock
            }

            Divider()

            aliasSection

            if let error = state.generalError {
                settingsErrorBlock(error)
            }

            Divider()

            settingsSection("codex 命令") {
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
                Text("暂无账号")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.accounts) { account in
                    aliasRow(account)
                }
                Text("命令示例: codex @\(state.accounts.first?.alias ?? "ash")")
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
                    Text("账号别名")
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
        state.accounts.isEmpty ? "暂无账号" : "\(state.accounts.count) 个账号"
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

            Button("保存") {
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
            settingToggle(
                title: "隐藏账号邮箱",
                isOn: Binding(
                    get: { state.hideAccountEmail },
                    set: { state.setHideAccountEmail($0) }
                )
            )
            .help("开启后保留邮箱前缀和域名，隐藏中间部分")

            settingToggle(
                title: "显示 Spark 额度",
                isOn: Binding(
                    get: { state.showSparkUsage },
                    set: { state.setShowSparkUsage($0) }
                )
            )
            .help("开启后，如果 ChatGPT 用量接口返回 Spark 或 codex_other 附加限额，会在账号列表中显示")

            settingToggle(
                title: "共享记录和状态",
                detail: "会话、goal、缓存、插件、技能",
                isOn: Binding(
                    get: { state.shareCodexData },
                    set: { state.setShareCodexData($0) }
                ),
                isDisabled: state.shareCodexDataBusy
            )
            .help("共享会话、goal、state_5.sqlite、memories、automations、worktrees、skills、plugins、图片和缓存；不共享登录、配置、环境变量和日志")

            settingToggle(
                title: "共享配置",
                detail: "config.toml、AGENTS、规则",
                isOn: Binding(
                    get: { state.shareCodexConfig },
                    set: { state.setShareCodexConfig($0) }
                ),
                isDisabled: state.shareCodexConfigBusy
            )
            .help("共享 config.toml、AGENTS.md、hooks.json、keybindings.json、rules 和 prompts；不共享 auth.json、环境变量和日志")

            settingToggle(
                title: "开机自启",
                isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                )
            )
            .help("使用 macOS 登录项；默认关闭")
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
                Text("状态")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                statusLabel(status)
            }

            if let real = status.detectedRealCodex {
                VStack(alignment: .leading, spacing: 5) {
                    pathRow(label: "入口", value: status.installPath)
                    pathRow(label: "真实", value: real)
                }
            } else {
                Text("未检测到 codex")
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
                    Button("卸载") { state.uninstallShim() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Spacer()

                Button(showCustomPath ? "收起" : "自定义路径") {
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
            case .missing: return ("未安装", .secondary)
            case .ours: return ("已接管", .green)
            case .foreign: return ("未接管", .secondary)
            }
        }()
        return Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
    }

    private func installLabel(_ status: ShimInstaller.Status) -> String {
        if status.shimNeedsUpdate { return "更新" }
        switch status.installed {
            case .missing: return "安装"
            case .ours: return "重装"
            case .foreign: return "接管"
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
            Text("当前终端仍会绕过接管")
                .font(.caption)
                .foregroundStyle(.orange)
            Spacer()
        }
    }

    private func shimErrorBlock(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("自动接管失败")
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
            Button("退出 Codex Accounts") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q", modifiers: [.command])
        }
    }
}
