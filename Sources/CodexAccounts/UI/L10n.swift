import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans
    case en

    var id: String { rawValue }

    static let defaultsKey = "appLanguage"

    static var current: AppLanguage {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let language = AppLanguage(rawValue: raw) else {
            return .system
        }
        return language
    }

    var resolved: AppLanguage {
        switch self {
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
            return preferred.hasPrefix("zh") ? .zhHans : .en
        case .zhHans, .en:
            return self
        }
    }

    var locale: Locale {
        switch resolved {
        case .system, .zhHans:
            return Locale(identifier: "zh_CN")
        case .en:
            return Locale(identifier: "en_US")
        }
    }

    func displayName(in uiLanguage: AppLanguage) -> String {
        switch uiLanguage.resolved {
        case .system, .zhHans:
            switch self {
            case .system: return "跟随系统"
            case .zhHans: return "简体中文"
            case .en: return "English"
            }
        case .en:
            switch self {
            case .system: return "System"
            case .zhHans: return "Simplified Chinese"
            case .en: return "English"
            }
        }
    }
}

enum L10nKey: String {
    case language
    case preferences
    case settings
    case accountAliases
    case codexCommand
    case noAccounts
    case accountCountFormat
    case commandExampleFormat
    case save
    case hideAccountEmail
    case hideAccountEmailHelp
    case showSparkUsage
    case showSparkUsageHelp
    case showUsageResetTime
    case showUsageResetTimeDetail
    case showUsageResetTimeHelp
    case showDailyUsageBaseline
    case showDailyUsageBaselineDetail
    case showDailyUsageBaselineHelp
    case dailyUsageBaselineHelpFormat
    case shareCodexData
    case shareCodexDataDetail
    case shareCodexDataHelp
    case shareCodexConfig
    case shareCodexConfigDetail
    case shareCodexConfigHelp
    case launchAtLogin
    case launchAtLoginHelp
    case status
    case entry
    case real
    case codexNotDetected
    case uninstall
    case collapse
    case customPath
    case shimMissing
    case shimManaged
    case shimUnmanaged
    case update
    case install
    case reinstall
    case takeover
    case terminalBypassesTakeover
    case autoTakeoverFailed
    case quitApp
    case activeAccountHelp
    case switchAccountHelp
    case current
    case removeAccountHelp
    case removeAccountFormat
    case removeAccountDetail
    case cancel
    case remove
    case expired
    case invalid
    case error
    case week
    case tomorrowFormat
    case pendingSwitchAfterTerminate
    case pendingSwitchKeepsRunning
    case codexRunning
    case lazyTerminate
    case `switch`
    case terminateCodexPrompt
    case back
    case terminateAndSwitch
    case processCountFormat
    case refreshingUsage
    case refreshUsageHelp
    case settingsHelp
    case updateInProgress
    case updatedAtFormat
    case noSuccessfulRefresh
    case lastSuccessfulRefreshFormat
    case existingCodexLoginFormat
    case close
    case cancelLogin
    case addAccount
    case cancelLoginHelp
    case addAccountHelp
    case loginFailedTitle
    case loginSucceededTitle
    case closeThisPage
    case oauthProviderReturnedErrorFormat
    case oauthStateMismatchPage
    case oauthMissingCodePage
    case oauthPortsUnavailable
    case oauthStateMismatch
    case oauthMissingCode
    case oauthProviderErrorFormat
    case oauthTokenExchangeFailedFormat
    case oauthCancelled
    case oauthCallbackStartFailed
    case oauthCallbackPermissionDenied
    case oauthCallbackNetworkErrorFormat
    case shimCodexNotFound
    case shimStillBypassesFormat
}

struct L10n {
    let language: AppLanguage

    init(language: AppLanguage = .current) {
        self.language = language
    }

    func text(_ key: L10nKey) -> String {
        Self.text(key, language: language)
    }

    func format(_ key: L10nKey, _ arguments: CVarArg...) -> String {
        Self.format(key, arguments, language: language)
    }

    static func text(_ key: L10nKey, language: AppLanguage = .current) -> String {
        let table = language.resolved == .en ? en : zhHans
        return table[key] ?? zhHans[key] ?? key.rawValue
    }

    static func format(_ key: L10nKey, _ arguments: CVarArg..., language: AppLanguage = .current) -> String {
        format(key, arguments, language: language)
    }

    private static func format(_ key: L10nKey, _ arguments: [CVarArg], language: AppLanguage) -> String {
        String(format: text(key, language: language), locale: language.locale, arguments: arguments)
    }

    private static let zhHans: [L10nKey: String] = [
        .language: "语言",
        .preferences: "偏好",
        .settings: "设置",
        .accountAliases: "账号别名",
        .codexCommand: "codex 命令",
        .noAccounts: "暂无账号",
        .accountCountFormat: "%d 个账号",
        .commandExampleFormat: "命令示例: codex @%@",
        .save: "保存",
        .hideAccountEmail: "隐藏账号邮箱",
        .hideAccountEmailHelp: "开启后保留邮箱前缀和域名，隐藏中间部分",
        .showSparkUsage: "显示 Spark 额度",
        .showSparkUsageHelp: "开启后，如果 ChatGPT 用量接口返回 Spark 或 codex_other 附加限额，会在账号列表中显示",
        .showUsageResetTime: "显示额度重置时间",
        .showUsageResetTimeDetail: "倒计时后显示几点或日期",
        .showUsageResetTimeHelp: "默认关闭；开启后在每个额度倒计时后追加具体重置时间，跨天显示日期",
        .showDailyUsageBaseline: "显示每日初始额度",
        .showDailyUsageBaselineDetail: "用浮标标出当天基线",
        .showDailyUsageBaselineHelp: "默认关闭；应用会持续记录当天第一次刷新到的额度作为基线，最多保留最近 8 天记录",
        .dailyUsageBaselineHelpFormat: "今日已用 %@ · 基线 %@",
        .shareCodexData: "共享记录和状态",
        .shareCodexDataDetail: "会话、goal、缓存、插件、技能",
        .shareCodexDataHelp: "共享会话、goal、memories、state/sqlite 状态库、附件、automations、worktrees、skills、plugins、图片和缓存；不共享登录、配置、环境变量和日志",
        .shareCodexConfig: "共享配置",
        .shareCodexConfigDetail: "config.toml、AGENTS、规则",
        .shareCodexConfigHelp: "共享 config.toml、AGENTS.md、hooks.json、keybindings.json、rules 和 prompts；不共享 auth.json、环境变量和日志",
        .launchAtLogin: "开机自启",
        .launchAtLoginHelp: "使用 macOS 登录项；默认关闭",
        .status: "状态",
        .entry: "入口",
        .real: "真实",
        .codexNotDetected: "未检测到 codex",
        .uninstall: "卸载",
        .collapse: "收起",
        .customPath: "自定义路径",
        .shimMissing: "未安装",
        .shimManaged: "已接管",
        .shimUnmanaged: "未接管",
        .update: "更新",
        .install: "安装",
        .reinstall: "重装",
        .takeover: "接管",
        .terminalBypassesTakeover: "当前终端仍会绕过接管",
        .autoTakeoverFailed: "自动接管失败",
        .quitApp: "退出 Codex Accounts",
        .activeAccountHelp: "当前活跃账户",
        .switchAccountHelp: "切换到此账户",
        .current: "当前",
        .removeAccountHelp: "移除账户",
        .removeAccountFormat: "移除 %@?",
        .removeAccountDetail: "退出登录并删除本地数据",
        .cancel: "取消",
        .remove: "移除",
        .expired: "过期",
        .invalid: "失效",
        .error: "错误",
        .week: "week",
        .tomorrowFormat: "明天 %@",
        .pendingSwitchAfterTerminate: "结束后会立即切换账号。",
        .pendingSwitchKeepsRunning: "已运行进程继续使用原账号，新启动 codex 使用新账号。",
        .codexRunning: "codex 正在运行",
        .lazyTerminate: "我很懒",
        .switch: "切换",
        .terminateCodexPrompt: "结束 codex?",
        .back: "返回",
        .terminateAndSwitch: "结束并切换",
        .processCountFormat: "%d 个进程",
        .refreshingUsage: "正在刷新用量",
        .refreshUsageHelp: "刷新所有账户的用量",
        .settingsHelp: "设置",
        .updateInProgress: "更新中",
        .updatedAtFormat: "更新 %@",
        .noSuccessfulRefresh: "暂无成功刷新",
        .lastSuccessfulRefreshFormat: "上次刷新成功：%@",
        .existingCodexLoginFormat: "现有 Codex 登录 · %@",
        .close: "关闭",
        .cancelLogin: "取消登录",
        .addAccount: "添加账户",
        .cancelLoginHelp: "停止等待浏览器登录",
        .addAccountHelp: "添加账户",
        .loginFailedTitle: "登录失败",
        .loginSucceededTitle: "登录成功",
        .closeThisPage: "可以关闭此页。",
        .oauthProviderReturnedErrorFormat: "OAuth provider returned an error: %@",
        .oauthStateMismatchPage: "OAuth state parameter mismatch.",
        .oauthMissingCodePage: "Missing authorization code.",
        .oauthPortsUnavailable: "本地登录回调端口 1455 和 1457 都不可用。请关闭其他正在登录的 Codex 或 Codex Accounts 窗口后重试。",
        .oauthStateMismatch: "登录回调校验失败。请重新点击「添加账户」，不要复用之前打开的登录页面。",
        .oauthMissingCode: "浏览器没有返回授权码。请重新登录一次。",
        .oauthProviderErrorFormat: "OpenAI 登录返回错误：%@",
        .oauthTokenExchangeFailedFormat: "换取登录凭证失败：%@",
        .oauthCancelled: "登录已取消或超时。",
        .oauthCallbackStartFailed: "本地登录回调服务启动失败。请退出其他正在登录的 Codex 或 Codex Accounts 进程后重试；如果仍然失败，重启 Codex Accounts。",
        .oauthCallbackPermissionDenied: "没有权限启动本地登录回调服务。请重新打开 Codex Accounts 后再试。",
        .oauthCallbackNetworkErrorFormat: "本地登录回调服务遇到网络错误（%d）。请稍后重试，或重启 Codex Accounts。",
        .shimCodexNotFound: "codex executable not found in interactive PATH",
        .shimStillBypassesFormat: "installed shim at %@, but the interactive shell still resolves codex to another executable\nPATH=%@"
    ]

    private static let en: [L10nKey: String] = [
        .language: "Language",
        .preferences: "Preferences",
        .settings: "Settings",
        .accountAliases: "Account Aliases",
        .codexCommand: "codex Command",
        .noAccounts: "No accounts",
        .accountCountFormat: "%d accounts",
        .commandExampleFormat: "Command example: codex @%@",
        .save: "Save",
        .hideAccountEmail: "Hide account emails",
        .hideAccountEmailHelp: "Keeps the email prefix and domain visible while masking the middle",
        .showSparkUsage: "Show Spark usage",
        .showSparkUsageHelp: "Shows Spark or codex_other extra limits in the account list when the ChatGPT usage API returns them",
        .showUsageResetTime: "Show reset time",
        .showUsageResetTimeDetail: "Show clock time or date after countdown",
        .showUsageResetTimeHelp: "Off by default; appends the concrete reset time after each usage countdown, with dates for future days",
        .showDailyUsageBaseline: "Show daily baseline",
        .showDailyUsageBaselineDetail: "Mark today's baseline on usage bars",
        .showDailyUsageBaselineHelp: "Off by default; the app continuously records the first usage value seen each day as the baseline and keeps at most the last 8 days",
        .dailyUsageBaselineHelpFormat: "Used today %@ · baseline %@",
        .shareCodexData: "Share history and state",
        .shareCodexDataDetail: "Sessions, goals, cache, plugins, skills",
        .shareCodexDataHelp: "Shares sessions, goals, memories, state/sqlite databases, attachments, automations, worktrees, skills, plugins, images, and cache; does not share auth, config, environment, or logs",
        .shareCodexConfig: "Share config",
        .shareCodexConfigDetail: "config.toml, AGENTS, rules",
        .shareCodexConfigHelp: "Shares config.toml, AGENTS.md, hooks.json, keybindings.json, rules, and prompts; does not share auth.json, environment, or logs",
        .launchAtLogin: "Launch at login",
        .launchAtLoginHelp: "Uses the macOS login item; off by default",
        .status: "Status",
        .entry: "Entry",
        .real: "Real",
        .codexNotDetected: "codex not detected",
        .uninstall: "Uninstall",
        .collapse: "Collapse",
        .customPath: "Custom path",
        .shimMissing: "Not installed",
        .shimManaged: "Managed",
        .shimUnmanaged: "Not managed",
        .update: "Update",
        .install: "Install",
        .reinstall: "Reinstall",
        .takeover: "Take over",
        .terminalBypassesTakeover: "The current terminal still bypasses takeover",
        .autoTakeoverFailed: "Auto takeover failed",
        .quitApp: "Quit Codex Accounts",
        .activeAccountHelp: "Current active account",
        .switchAccountHelp: "Switch to this account",
        .current: "Current",
        .removeAccountHelp: "Remove account",
        .removeAccountFormat: "Remove %@?",
        .removeAccountDetail: "Sign out and delete local data",
        .cancel: "Cancel",
        .remove: "Remove",
        .expired: "Expired",
        .invalid: "Invalid",
        .error: "Error",
        .week: "week",
        .tomorrowFormat: "Tomorrow %@",
        .pendingSwitchAfterTerminate: "The account will switch immediately after termination.",
        .pendingSwitchKeepsRunning: "Running processes keep the old account; new codex processes use the new account.",
        .codexRunning: "codex is running",
        .lazyTerminate: "Terminate",
        .switch: "Switch",
        .terminateCodexPrompt: "Terminate codex?",
        .back: "Back",
        .terminateAndSwitch: "Terminate and switch",
        .processCountFormat: "%d processes",
        .refreshingUsage: "Refreshing usage",
        .refreshUsageHelp: "Refresh usage for all accounts",
        .settingsHelp: "Settings",
        .updateInProgress: "Updating",
        .updatedAtFormat: "Updated %@",
        .noSuccessfulRefresh: "No successful refresh yet",
        .lastSuccessfulRefreshFormat: "Last successful refresh: %@",
        .existingCodexLoginFormat: "Existing Codex login · %@",
        .close: "Close",
        .cancelLogin: "Cancel login",
        .addAccount: "Add account",
        .cancelLoginHelp: "Stop waiting for browser login",
        .addAccountHelp: "Add account",
        .loginFailedTitle: "Login Failed",
        .loginSucceededTitle: "Login Succeeded",
        .closeThisPage: "You can close this page.",
        .oauthProviderReturnedErrorFormat: "OAuth provider returned an error: %@",
        .oauthStateMismatchPage: "OAuth state parameter mismatch.",
        .oauthMissingCodePage: "Missing authorization code.",
        .oauthPortsUnavailable: "Local login callback ports 1455 and 1457 are both unavailable. Close other Codex or Codex Accounts login windows and try again.",
        .oauthStateMismatch: "Login callback verification failed. Click Add account again, and do not reuse the previous login page.",
        .oauthMissingCode: "The browser did not return an authorization code. Please sign in again.",
        .oauthProviderErrorFormat: "OpenAI login returned an error: %@",
        .oauthTokenExchangeFailedFormat: "Failed to exchange login credentials: %@",
        .oauthCancelled: "Login was cancelled or timed out.",
        .oauthCallbackStartFailed: "Local login callback service failed to start. Close other running Codex or Codex Accounts processes and try again; if it still fails, restart Codex Accounts.",
        .oauthCallbackPermissionDenied: "No permission to start the local login callback service. Reopen Codex Accounts and try again.",
        .oauthCallbackNetworkErrorFormat: "The local login callback service hit a network error (%d). Try again later or restart Codex Accounts.",
        .shimCodexNotFound: "codex executable not found in interactive PATH",
        .shimStillBypassesFormat: "installed shim at %@, but the interactive shell still resolves codex to another executable\nPATH=%@"
    ]
}
