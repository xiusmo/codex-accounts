import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    private static let hideAccountEmailKey = "hideAccountEmail"
    private static let showSparkUsageKey = "showSparkUsage"
    private static let showUsageResetTimeKey = "showUsageResetTime"
    private static let showDailyUsageBaselineKey = "showDailyUsageBaseline"
    private static let lastAutomaticDailyBaselineRefreshDayKey = "lastAutomaticDailyBaselineRefreshDay"
    private static let automaticDailyBaselineRefreshLeeway: TimeInterval = 60
    private static let shareCodexDataKey = "shareCodexData"
    private static let shareCodexConfigKey = "shareCodexConfig"
    private static let accountMoveAnimation = Animation.spring(response: 0.34, dampingFraction: 0.84, blendDuration: 0.06)
    private static let usageRefreshCooldown: TimeInterval = 60

    @Published var accounts: [Account] = []
    @Published var usage: [String: UsageState] = [:]
    @Published var loginInProgress = false
    @Published var loginError: String?
    @Published var generalError: String?
    @Published var shimStatus: ShimInstaller.Status?
    @Published var shimError: String?
    @Published var runningCodexHits: [CodexProcessDetector.Hit] = []
    @Published var pendingSwitch: Account?
    @Published var confirmingTerminateRunningCodex = false
    @Published var appLanguage: AppLanguage
    @Published var hideAccountEmail: Bool
    @Published var showSparkUsage: Bool
    @Published var showUsageResetTime: Bool
    @Published var showDailyUsageBaseline: Bool
    @Published var dailyUsageBaselines: [String: [String: UsageBaselineSnapshot]]
    @Published var shareCodexData: Bool
    @Published var shareCodexDataBusy = false
    @Published var shareCodexConfig: Bool
    @Published var shareCodexConfigBusy = false
    @Published var launchAtLogin: Bool
    @Published var codexImportCandidates: [CodexImportCandidate] = []
    @Published var lastSuccessfulUsageRefreshAt: Date?
    @Published var usageRefreshInProgress = false

    let store: AccountStore
    let usageClient: UsageClient
    let tokenRefresher: OAuthTokenRefresher
    let shim: ShimInstaller
    let oauth: OAuthLogin
    let logout: OAuthLogout
    let sharedData: SharedCodexData
    private let usageBaselineStore: UsageBaselineStore
    private var loginTask: Task<Void, Never>?
    private var shareCodexDataTask: Task<Void, Never>?
    private var shareCodexConfigTask: Task<Void, Never>?
    private var dailyBaselineRefreshTask: Task<Void, Never>?
    private var loginGeneration = 0
    private var lastAutoTakeoverAttemptKey: String?
    private var lastUsageRefreshStartedAt: Date?

    init(store: AccountStore = AccountStore(),
         usageClient: UsageClient = UsageClient(),
         tokenRefresher: OAuthTokenRefresher = OAuthTokenRefresher(),
         shim: ShimInstaller = ShimInstaller(),
         oauth: OAuthLogin = OAuthLogin(),
         logout: OAuthLogout = OAuthLogout(),
         sharedData: SharedCodexData? = nil,
         usageBaselineStore: UsageBaselineStore = UsageBaselineStore()) {
        self.appLanguage = AppLanguage.current
        self.hideAccountEmail = UserDefaults.standard.bool(forKey: Self.hideAccountEmailKey)
        self.showSparkUsage = UserDefaults.standard.object(forKey: Self.showSparkUsageKey) as? Bool ?? true
        self.showUsageResetTime = UserDefaults.standard.bool(forKey: Self.showUsageResetTimeKey)
        self.showDailyUsageBaseline = UserDefaults.standard.bool(forKey: Self.showDailyUsageBaselineKey)
        self.dailyUsageBaselines = usageBaselineStore.today()
        self.shareCodexData = UserDefaults.standard.bool(forKey: Self.shareCodexDataKey)
        self.shareCodexConfig = UserDefaults.standard.bool(forKey: Self.shareCodexConfigKey)
        self.launchAtLogin = LaunchAtLogin.isEnabled
        self.store = store
        self.usageClient = usageClient
        self.tokenRefresher = tokenRefresher
        self.shim = shim
        self.oauth = oauth
        self.logout = logout
        self.sharedData = sharedData ?? SharedCodexData(accountsBaseURL: store.baseURL)
        self.usageBaselineStore = usageBaselineStore

        Task { @MainActor in
            self.reload()
            if self.shareCodexData {
                self.syncSharedCodexData(enabled: true, previous: true, rollbackOnFailure: false)
            }
            if self.shareCodexConfig {
                self.syncSharedCodexConfig(enabled: true, previous: true, rollbackOnFailure: false)
            }
            self.startDailyBaselineRefreshSchedulerIfNeeded()
        }
    }

    // MARK: - Loading

    func reload(animated: Bool = false) {
        do {
            let loaded = try store.loadAll()
            let importCandidates = store.discoverCodexImportCandidates(managedAccounts: loaded)
            let filteredUsage = usage.filter { key, _ in loaded.contains(where: { $0.directoryName == key }) }

            let applyLoadedState = {
                self.accounts = loaded
                self.codexImportCandidates = importCandidates
                self.usage = filteredUsage
            }
            if animated {
                withAnimation(Self.accountMoveAnimation) {
                    applyLoadedState()
                }
            } else {
                applyLoadedState()
            }
        } catch {
            generalError = RawErrorText.string(error)
        }
        ensureShimTakeover()
    }

    func refreshShimStatus() {
        shimStatus = shim.currentStatus()
    }

    func ensureShimTakeover() {
        autoTakeoverShimIfNeeded()
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    func setAppLanguage(_ language: AppLanguage) {
        appLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.defaultsKey)
    }

    func setHideAccountEmail(_ hidden: Bool) {
        hideAccountEmail = hidden
        UserDefaults.standard.set(hidden, forKey: Self.hideAccountEmailKey)
    }

    func setShowSparkUsage(_ enabled: Bool) {
        showSparkUsage = enabled
        UserDefaults.standard.set(enabled, forKey: Self.showSparkUsageKey)
    }

    func setShowUsageResetTime(_ enabled: Bool) {
        showUsageResetTime = enabled
        UserDefaults.standard.set(enabled, forKey: Self.showUsageResetTimeKey)
    }

    func setShowDailyUsageBaseline(_ enabled: Bool) {
        showDailyUsageBaseline = enabled
        UserDefaults.standard.set(enabled, forKey: Self.showDailyUsageBaselineKey)
        dailyUsageBaselines = usageBaselineStore.today()
        if enabled {
            startDailyBaselineRefreshSchedulerIfNeeded()
        } else {
            dailyBaselineRefreshTask?.cancel()
            dailyBaselineRefreshTask = nil
        }
    }

    func setShareCodexData(_ enabled: Bool) {
        guard !shareCodexDataBusy, enabled != shareCodexData else { return }
        let previous = shareCodexData
        shareCodexData = enabled
        UserDefaults.standard.set(enabled, forKey: Self.shareCodexDataKey)
        syncSharedCodexData(enabled: enabled, previous: previous, rollbackOnFailure: true)
    }

    func setShareCodexConfig(_ enabled: Bool) {
        guard !shareCodexConfigBusy, enabled != shareCodexConfig else { return }
        let previous = shareCodexConfig
        shareCodexConfig = enabled
        UserDefaults.standard.set(enabled, forKey: Self.shareCodexConfigKey)
        syncSharedCodexConfig(enabled: enabled, previous: previous, rollbackOnFailure: true)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != launchAtLogin else { return }
        let previous = launchAtLogin
        launchAtLogin = enabled
        do {
            try LaunchAtLogin.setEnabled(enabled)
            refreshLaunchAtLoginStatus()
        } catch {
            launchAtLogin = previous
            generalError = RawErrorText.string(error)
        }
    }

    func setAlias(_ alias: String, for account: Account) {
        do {
            try store.setAlias(alias, for: account.directoryName)
            reload(animated: true)
        } catch {
            generalError = RawErrorText.string(error)
        }
    }

    private func syncSharedCodexData(enabled: Bool, previous: Bool, rollbackOnFailure: Bool) {
        shareCodexDataTask?.cancel()
        shareCodexDataBusy = true
        let baseURL = store.baseURL

        shareCodexDataTask = Task {
            do {
                try await Self.applySharedCodexData(enabled: enabled, baseURL: baseURL)
                await MainActor.run {
                    guard self.shareCodexData == enabled else { return }
                    self.shareCodexDataBusy = false
                    self.reload(animated: true)
                }
            } catch {
                await MainActor.run {
                    if rollbackOnFailure, self.shareCodexData == enabled {
                        self.shareCodexData = previous
                        UserDefaults.standard.set(previous, forKey: Self.shareCodexDataKey)
                    }
                    self.shareCodexDataBusy = false
                    self.generalError = RawErrorText.string(error)
                }
            }
        }
    }

    private nonisolated static func applySharedCodexData(enabled: Bool, baseURL: URL) async throws {
        try await Task.detached(priority: .utility) {
            let store = AccountStore(baseURL: baseURL)
            let loaded = try store.loadAll()
            let sharedData = SharedCodexData(accountsBaseURL: baseURL)
            if enabled {
                try sharedData.enable(for: loaded)
            } else {
                try sharedData.disable(for: loaded)
            }
        }.value
    }

    private func reapplyEnabledSharing() {
        if shareCodexData, !shareCodexDataBusy {
            syncSharedCodexData(enabled: true, previous: true, rollbackOnFailure: false)
        }
        if shareCodexConfig, !shareCodexConfigBusy {
            syncSharedCodexConfig(enabled: true, previous: true, rollbackOnFailure: false)
        }
    }

    private func syncSharedCodexConfig(enabled: Bool, previous: Bool, rollbackOnFailure: Bool) {
        shareCodexConfigTask?.cancel()
        shareCodexConfigBusy = true
        let baseURL = store.baseURL

        shareCodexConfigTask = Task {
            do {
                try await Self.applySharedCodexConfig(enabled: enabled, baseURL: baseURL)
                await MainActor.run {
                    guard self.shareCodexConfig == enabled else { return }
                    self.shareCodexConfigBusy = false
                    self.reload(animated: true)
                }
            } catch {
                await MainActor.run {
                    if rollbackOnFailure, self.shareCodexConfig == enabled {
                        self.shareCodexConfig = previous
                        UserDefaults.standard.set(previous, forKey: Self.shareCodexConfigKey)
                    }
                    self.shareCodexConfigBusy = false
                    self.generalError = RawErrorText.string(error)
                }
            }
        }
    }

    private nonisolated static func applySharedCodexConfig(enabled: Bool, baseURL: URL) async throws {
        try await Task.detached(priority: .utility) {
            let store = AccountStore(baseURL: baseURL)
            let loaded = try store.loadAll()
            let sharedData = SharedCodexData(accountsBaseURL: baseURL)
            if enabled {
                try sharedData.enableConfig(for: loaded)
            } else {
                try sharedData.disableConfig(for: loaded)
            }
        }.value
    }

    // MARK: - Usage refresh (on popover open / manual refresh)

    func refreshAllUsageIfStale() async {
        dailyUsageBaselines = usageBaselineStore.today()
        guard !usageRefreshInProgress else { return }

        let now = Date()
        if let lastUsageRefreshStartedAt,
           now.timeIntervalSince(lastUsageRefreshStartedAt) < Self.usageRefreshCooldown {
            return
        }

        await refreshAllUsage()
    }

    func refreshAllUsage() async {
        guard !usageRefreshInProgress else { return }
        dailyUsageBaselines = usageBaselineStore.today()
        lastUsageRefreshStartedAt = Date()
        usageRefreshInProgress = true
        defer { usageRefreshInProgress = false }

        let snapshot = accounts
        for acc in snapshot {
            if usage[acc.directoryName] == nil || usage[acc.directoryName] == .idle {
                usage[acc.directoryName] = .loading
            }
        }
        await withTaskGroup(of: (String, UsageState).self) { group in
            var hasSuccessfulUsage = false
            for acc in snapshot {
                group.addTask { [usageClient, tokenRefresher] in
                    let result = await Self.fetchUsageRefreshingIfNeeded(
                        account: acc,
                        usageClient: usageClient,
                        tokenRefresher: tokenRefresher
                    )
                    return (acc.directoryName, result)
                }
            }
            for await (key, value) in group {
                if case .loaded = value {
                    hasSuccessfulUsage = true
                    dailyUsageBaselines = usageBaselineStore.recordToday(accountKey: key, state: value)
                }
                withAnimation(Self.accountMoveAnimation) {
                    usage[key] = value
                }
            }
            if hasSuccessfulUsage {
                lastSuccessfulUsageRefreshAt = Date()
            }
        }
    }

    private func startDailyBaselineRefreshSchedulerIfNeeded() {
        dailyBaselineRefreshTask?.cancel()
        dailyBaselineRefreshTask = nil
        guard showDailyUsageBaseline else { return }

        dailyBaselineRefreshTask = Task { @MainActor [weak self] in
            await self?.refreshDailyBaselineAfterMidnightIfNeeded()
            while !Task.isCancelled {
                let delay = Self.secondsUntilNextLocalMidnightRefresh()
                try? await Task.sleep(nanoseconds: Self.nanoseconds(for: delay))
                guard !Task.isCancelled else { return }
                await self?.refreshDailyBaselineAfterMidnightIfNeeded()
            }
        }
    }

    private func refreshDailyBaselineAfterMidnightIfNeeded() async {
        guard showDailyUsageBaseline else { return }
        let accountKeys = accounts.map(\.directoryName)
        guard !accountKeys.isEmpty else { return }

        let todayKey = usageBaselineStore.dayKey()
        if UserDefaults.standard.string(forKey: Self.lastAutomaticDailyBaselineRefreshDayKey) == todayKey {
            return
        }

        if usageBaselineStore.hasBaselineToday(for: accountKeys) {
            UserDefaults.standard.set(todayKey, forKey: Self.lastAutomaticDailyBaselineRefreshDayKey)
            return
        }

        await refreshAllUsage()

        if usageBaselineStore.hasBaselineToday(for: accountKeys) {
            UserDefaults.standard.set(todayKey, forKey: Self.lastAutomaticDailyBaselineRefreshDayKey)
        }
    }

    static func nextLocalMidnightRefreshDate(
        after date: Date = .now,
        calendar: Calendar = .current
    ) -> Date {
        let startOfToday = calendar.startOfDay(for: date)
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? date.addingTimeInterval(24 * 60 * 60)
        return nextMidnight.addingTimeInterval(automaticDailyBaselineRefreshLeeway)
    }

    private static func secondsUntilNextLocalMidnightRefresh(
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TimeInterval {
        max(1, nextLocalMidnightRefreshDate(after: now, calendar: calendar).timeIntervalSince(now))
    }

    private static func nanoseconds(for seconds: TimeInterval) -> UInt64 {
        UInt64(max(1, seconds) * 1_000_000_000)
    }

    private nonisolated static func fetchUsageRefreshingIfNeeded(
        account: Account,
        usageClient: UsageClient,
        tokenRefresher: OAuthTokenRefresher
    ) async -> UsageState {
        var didRefresh = false
        if account.accessTokenExpired {
            do {
                try await tokenRefresher.refreshAuth(in: account.homeDirectory)
                didRefresh = true
            } catch {
                return stateForRefreshFailure(error)
            }
        }

        let first = await usageClient.fetchUsage(for: account)
        guard case .tokenExpired = first, !didRefresh else {
            return first
        }

        do {
            try await tokenRefresher.refreshAuth(in: account.homeDirectory)
        } catch {
            return stateForRefreshFailure(error)
        }

        let second = await usageClient.fetchUsage(for: account)
        if case let .tokenExpired(raw) = second {
            return .tokenExpired(raw)
        }
        return second
    }

    private nonisolated static func stateForRefreshFailure(_ error: Error) -> UsageState {
        let raw = RawErrorText.string(error)
        let lower = raw.lowercased()
        if lower.contains("refresh_token_expired") || lower.contains("expired") {
            return .tokenExpired(raw)
        }
        if lower.contains("refresh_token_reused")
            || lower.contains("refresh_token_invalidated")
            || lower.contains("invalid")
            || lower.contains("revoked") {
            return .authInvalid(raw)
        }
        return .failed(raw)
    }

    // MARK: - Switch active account

    /// First-pass switch: if codex is running, defer to a confirmation step.
    func requestSwitch(to account: Account) {
        guard !account.isActive else { return }
        Task {
            let hits = await CodexProcessDetector.runningInstances()
            guard let latest = accounts.first(where: { $0.directoryName == account.directoryName }),
                  !latest.isActive else {
                return
            }
            runningCodexHits = hits
            if hits.isEmpty {
                performSwitch(to: latest)
            } else {
                confirmingTerminateRunningCodex = false
                pendingSwitch = latest
            }
        }
    }

    func confirmPendingSwitch() {
        guard let account = pendingSwitch else { return }
        pendingSwitch = nil
        runningCodexHits = []
        confirmingTerminateRunningCodex = false
        performSwitch(to: account)
    }

    func cancelPendingSwitch() {
        pendingSwitch = nil
        runningCodexHits = []
        confirmingTerminateRunningCodex = false
    }

    func requestTerminateRunningCodex() {
        confirmingTerminateRunningCodex = true
    }

    func cancelTerminateRunningCodex() {
        confirmingTerminateRunningCodex = false
    }

    func confirmTerminateRunningCodexAndSwitch() {
        guard let account = pendingSwitch else { return }
        let hits = runningCodexHits
        Task {
            let failures = await CodexProcessDetector.terminate(hits)
            if failures.isEmpty {
                pendingSwitch = nil
                runningCodexHits = []
                confirmingTerminateRunningCodex = false
                performSwitch(to: account)
            } else {
                generalError = failures.map(\.description).joined(separator: "\n")
                confirmingTerminateRunningCodex = false
            }
        }
    }

    private func performSwitch(to account: Account) {
        do {
            try store.setActive(account.directoryName)
            reload(animated: true)
            Task { await refreshAllUsage() }
        } catch {
            generalError = RawErrorText.string(error)
        }
    }

    // MARK: - Add / remove

    func startAddAccount() {
        guard !loginInProgress else { return }
        loginInProgress = true
        loginError = nil
        loginGeneration += 1
        let generation = loginGeneration
        loginTask = Task { [oauth, store] in
            do {
                let authJson = try await oauth.login()
                try Task.checkCancellation()
                let name = try store.saveNewAccount(authJson: authJson)
                // If no active account yet, make this one active so the shim has something to use.
                if store.readActiveName() == nil {
                    try store.setActive(name)
                }
                let loaded = try store.loadAll()
                await MainActor.run {
                    guard self.loginGeneration == generation else { return }
                    self.loginTask = nil
                    self.loginInProgress = false
                    self.accounts = loaded
                    self.reapplyEnabledSharing()
                    self.ensureShimTakeover()
                    Task { await self.refreshAllUsage() }
                }
            } catch {
                let wasCancelled = error is CancellationError || Task.isCancelled
                await MainActor.run {
                    guard self.loginGeneration == generation else { return }
                    self.loginTask = nil
                    self.loginInProgress = false
                    self.loginError = wasCancelled ? nil : RawErrorText.string(error)
                }
            }
        }
    }

    func cancelAddAccount() {
        guard loginInProgress else { return }
        loginGeneration += 1
        loginTask?.cancel()
        loginTask = nil
        loginInProgress = false
        loginError = nil
    }

    func removeAccount(_ account: Account) {
        Task { [store, logout] in
            do {
                let authJson = try? store.readAuth(directoryName: account.directoryName)
                // Match Codex CLI: revocation is best-effort; local logout still completes.
                try? await logout.revoke(authJson: authJson)
                try store.removeAccount(directoryName: account.directoryName)
                await MainActor.run {
                    self.reload()
                    Task { await self.refreshAllUsage() }
                }
            } catch {
                await MainActor.run {
                    self.generalError = RawErrorText.string(error)
                }
            }
        }
    }

    func takeoverCodexAccount(_ candidate: CodexImportCandidate) {
        do {
            let name = try store.importAuth(from: candidate.sourceURL)
            try store.setActive(name)
            reload()
            reapplyEnabledSharing()
            Task { await refreshAllUsage() }
        } catch {
            generalError = RawErrorText.string(error)
        }
    }

    // MARK: - Shim

    func installShim(realCodex: String) {
        do {
            try shim.install(realCodexPath: realCodex)
            lastAutoTakeoverAttemptKey = nil
            shimError = nil
            refreshShimStatus()
        } catch {
            shimError = RawErrorText.string(error)
            refreshShimStatus()
        }
    }

    func uninstallShim() {
        do {
            try shim.uninstall()
            lastAutoTakeoverAttemptKey = nil
            shimError = nil
            refreshShimStatus()
        } catch {
            shimError = RawErrorText.string(error)
            refreshShimStatus()
        }
    }

    private func autoTakeoverShimIfNeeded() {
        let status = shim.currentStatus()
        shimStatus = status
        guard !status.pathPrecedenceOK || status.shimNeedsUpdate else {
            lastAutoTakeoverAttemptKey = nil
            shimError = nil
            return
        }

        let attemptKey = autoTakeoverAttemptKey(for: status)
        guard lastAutoTakeoverAttemptKey != attemptKey else { return }
        lastAutoTakeoverAttemptKey = attemptKey

        do {
            guard let realCodex = status.detectedRealCodex, !realCodex.isEmpty else {
                throw ShimAutoTakeoverError.codexNotFound
            }
            try shim.install(realCodexPath: realCodex)
            let refreshed = shim.currentStatus()
            shimStatus = refreshed
            guard refreshed.pathPrecedenceOK else {
                throw ShimAutoTakeoverError.commandStillBypassesShim(
                    installPath: refreshed.installPath,
                    interactivePATH: refreshed.interactivePATH
                )
            }
            lastAutoTakeoverAttemptKey = nil
            shimError = nil
        } catch {
            shimError = RawErrorText.string(error)
            refreshShimStatus()
        }
    }

    private func autoTakeoverAttemptKey(for status: ShimInstaller.Status) -> String {
        let installed: String = {
            switch status.installed {
            case .missing:
                return "missing"
            case .foreign:
                return "foreign"
            case .ours(let realCodex):
                return "ours:\(realCodex)"
            }
        }()
        return [
            installed,
            status.installPath,
            status.detectedRealCodex ?? "",
            String(status.pathPrecedenceOK),
            String(status.shimNeedsUpdate)
        ].joined(separator: "\u{1f}")
    }
}

private enum ShimAutoTakeoverError: Error, CustomStringConvertible {
    case codexNotFound
    case commandStillBypassesShim(installPath: String, interactivePATH: String)

    var description: String {
        switch self {
        case .codexNotFound:
            return L10n.text(.shimCodexNotFound)
        case let .commandStillBypassesShim(installPath, interactivePATH):
            return L10n.format(.shimStillBypassesFormat, installPath, interactivePATH)
        }
    }
}
