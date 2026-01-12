//
//  ClaudeUsageManager.swift
//  AgentNotch
//
//  Manages Claude API usage quota fetching and display
//

import Foundation
import Combine
import os.log

@MainActor
final class ClaudeUsageManager: ObservableObject {
    static let shared = ClaudeUsageManager()

    // MARK: - Logger

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AgentNotch", category: "ClaudeUsage")

    // MARK: - Published Properties

    @Published private(set) var usageData: ClaudeUsageData = .empty
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: ClaudeUsageError?
    @Published private(set) var isConfigured: Bool = false

    /// Current monitoring mode (for smart refresh)
    @Published private(set) var currentMonitoringMode: UsageMonitoringMode = .active

    // MARK: - Private Properties

    private let baseURL = "https://claude.ai/api/organizations"
    private var refreshTimer: Timer?
    private var lastUtilization: Double = 0
    private var unchangedCount: Int = 0
    private var lastManualRefreshTime: Date = .distantPast
    private let manualRefreshDebounce: TimeInterval = 10  // 10 seconds between manual refreshes

    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    // MARK: - Computed Properties

    /// Session key from Keychain
    var sessionKey: String? {
        get { KeychainHelper.load(key: KeychainHelper.claudeSessionKey) }
        set {
            if let value = newValue, !value.isEmpty {
                _ = KeychainHelper.save(key: KeychainHelper.claudeSessionKey, value: value)
            } else {
                KeychainHelper.delete(key: KeychainHelper.claudeSessionKey)
            }
            updateConfiguredState()
        }
    }

    /// Organization ID from Keychain
    var organizationId: String? {
        get { KeychainHelper.load(key: KeychainHelper.claudeOrganizationId) }
        set {
            if let value = newValue, !value.isEmpty {
                _ = KeychainHelper.save(key: KeychainHelper.claudeOrganizationId, value: value)
            } else {
                KeychainHelper.delete(key: KeychainHelper.claudeOrganizationId)
            }
            updateConfiguredState()
        }
    }

    /// Cloudflare clearance cookie from Keychain (needed to bypass Cloudflare)
    var cfClearance: String? {
        get { KeychainHelper.load(key: KeychainHelper.claudeCfClearance) }
        set {
            if let value = newValue, !value.isEmpty {
                _ = KeychainHelper.save(key: KeychainHelper.claudeCfClearance, value: value)
            } else {
                KeychainHelper.delete(key: KeychainHelper.claudeCfClearance)
            }
        }
    }

    // MARK: - Initialization

    private init() {
        updateConfiguredState()
    }

    // MARK: - Public Methods

    /// Start automatic refresh polling
    func startRefreshing() {
        guard isConfigured else {
            logger.info("Cannot start refreshing: not configured")
            return
        }

        stopRefreshing()

        // Initial fetch
        Task {
            await fetchUsage()
        }

        // Start timer based on refresh mode
        scheduleNextRefresh()
    }

    /// Stop automatic refresh polling
    func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Manual refresh (with debounce)
    func manualRefresh() async {
        let now = Date()
        guard now.timeIntervalSince(lastManualRefreshTime) >= manualRefreshDebounce else {
            logger.debug("Manual refresh debounced")
            return
        }

        lastManualRefreshTime = now

        // Reset to active mode on manual refresh
        let settings = AppSettings.shared
        if settings.claudeUsageRefreshMode == "smart" {
            currentMonitoringMode = .active
            unchangedCount = 0
        }

        await fetchUsage()
    }

    /// Fetch usage data from Claude API
    func fetchUsage() async {
        guard let sessionKey = sessionKey, !sessionKey.isEmpty else {
            lastError = .noCredentials
            return
        }

        // Auto-discover organization ID if not set
        if organizationId == nil {
            await fetchOrganizationId()
        }

        guard let orgId = organizationId else {
            lastError = .noCredentials
            return
        }

        isLoading = true
        lastError = nil

        do {
            // Fetch main usage and extra usage in parallel
            async let mainUsage = fetchMainUsage(orgId: orgId, sessionKey: sessionKey)
            async let extraUsage = fetchExtraUsage(orgId: orgId, sessionKey: sessionKey)

            let main = try await mainUsage
            let extra = try? await extraUsage  // Extra usage is optional

            usageData = ClaudeUsageData(
                fiveHour: main.fiveHour,
                sevenDay: main.sevenDay,
                opus: main.opus,
                sonnet: main.sonnet,
                extraUsage: extra,
                fetchedAt: Date()
            )

            // Update smart monitoring mode
            let settings = AppSettings.shared
            if settings.claudeUsageRefreshMode == "smart" {
                updateSmartMonitoringMode(currentUtilization: main.fiveHour?.percentage ?? 0)
            }

            logger.info("Usage fetched: 5hr=\(main.fiveHour?.percentage ?? 0, format: .fixed(precision: 1))%")

        } catch let error as ClaudeUsageError {
            lastError = error
            logger.error("Failed to fetch usage: \(error.localizedDescription)")
        } catch {
            lastError = .networkError(error)
            logger.error("Network error: \(error.localizedDescription)")
        }

        isLoading = false
    }

    /// Clear all stored credentials
    func clearCredentials() {
        sessionKey = nil
        organizationId = nil
        cfClearance = nil
        usageData = .empty
        lastError = nil
        stopRefreshing()
    }

    /// Validate session key format
    func isValidSessionKey(_ key: String) -> Bool {
        return !key.isEmpty && key.count >= 20 && key.count <= 500
    }

    // MARK: - Private Methods

    private func updateConfiguredState() {
        isConfigured = !(sessionKey?.isEmpty ?? true)
    }

    private func scheduleNextRefresh() {
        let settings = AppSettings.shared
        let interval: TimeInterval

        if settings.claudeUsageRefreshMode == "smart" {
            interval = currentMonitoringMode.interval
        } else {
            interval = TimeInterval(settings.claudeUsageRefreshInterval)
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchUsage()
                self?.scheduleNextRefresh()
            }
        }
    }

    private func updateSmartMonitoringMode(currentUtilization: Double) {
        // Check if utilization changed (> 0.01 difference)
        let hasChanged = abs(currentUtilization - lastUtilization) > 0.01

        if hasChanged {
            // Activity detected - back to active mode
            currentMonitoringMode = .active
            unchangedCount = 0
        } else {
            // No change - progress through idle modes
            unchangedCount += 1

            let newMode: UsageMonitoringMode? = {
                switch currentMonitoringMode {
                case .active:
                    return unchangedCount >= 3 ? .idleShort : nil
                case .idleShort:
                    return unchangedCount >= 6 ? .idleMedium : nil
                case .idleMedium:
                    return unchangedCount >= 12 ? .idleLong : nil
                case .idleLong:
                    return nil
                }
            }()

            if let newMode = newMode {
                currentMonitoringMode = newMode
                logger.debug("Monitoring mode changed to: \(newMode.rawValue)")
            }
        }

        lastUtilization = currentUtilization
    }

    // MARK: - API Calls

    private func fetchOrganizationId() async {
        guard let sessionKey = sessionKey else { return }

        let url = URL(string: baseURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request, sessionKey: sessionKey)

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return
            }

            guard httpResponse.statusCode == 200 else {
                logger.error("Failed to fetch organizations: HTTP \(httpResponse.statusCode)")
                return
            }

            let organizations = try JSONDecoder().decode([ClaudeOrganization].self, from: data)

            if let firstOrg = organizations.first {
                organizationId = firstOrg.uuid
                logger.info("Auto-discovered organization: \(firstOrg.name) (\(firstOrg.uuid))")
            }
        } catch {
            logger.error("Failed to fetch organizations: \(error.localizedDescription)")
        }
    }

    private func fetchMainUsage(orgId: String, sessionKey: String) async throws -> (
        fiveHour: ClaudeUsageData.LimitData?,
        sevenDay: ClaudeUsageData.LimitData?,
        opus: ClaudeUsageData.LimitData?,
        sonnet: ClaudeUsageData.LimitData?
    ) {
        let url = URL(string: "\(baseURL)/\(orgId)/usage")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request, sessionKey: sessionKey)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeUsageError.noData
        }

        // Check for Cloudflare block
        if let responseString = String(data: data, encoding: .utf8),
           responseString.contains("<!DOCTYPE html>") || responseString.contains("<html") {
            throw ClaudeUsageError.cloudflareBlocked
        }

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            throw ClaudeUsageError.unauthorized
        case 403:
            // Check if it's a permission error
            if let errorResponse = try? JSONDecoder().decode(ClaudeAPIErrorResponse.self, from: data),
               errorResponse.error.type == "permission_error" {
                throw ClaudeUsageError.sessionExpired
            }
            throw ClaudeUsageError.cloudflareBlocked
        case 429:
            throw ClaudeUsageError.rateLimited
        default:
            throw ClaudeUsageError.httpError(statusCode: httpResponse.statusCode)
        }

        let usageResponse = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)

        return (
            fiveHour: parseLimitData(usageResponse.fiveHour),
            sevenDay: parseLimitDataOptional(usageResponse.sevenDay),
            opus: parseLimitDataOptional(usageResponse.sevenDayOpus),
            sonnet: parseLimitDataOptional(usageResponse.sevenDaySonnet)
        )
    }

    private func fetchExtraUsage(orgId: String, sessionKey: String) async throws -> ClaudeUsageData.ExtraUsageData? {
        let url = URL(string: "\(baseURL)/\(orgId)/overage_spend_limit")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request, sessionKey: sessionKey)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil  // Extra usage not available is not an error
        }

        let extraResponse = try JSONDecoder().decode(ClaudeExtraUsageResponse.self, from: data)

        let usedDollars = extraResponse.balanceCents.map { Double($0) / 100.0 }
        let limitDollars = extraResponse.spendLimitAmountCents.map { Double($0) / 100.0 }

        return ClaudeUsageData.ExtraUsageData(
            enabled: true,
            usedDollars: usedDollars,
            limitDollars: limitDollars,
            currency: extraResponse.spendLimitCurrency
        )
    }

    private func parseLimitData(_ limit: ClaudeUsageResponse.LimitUsage) -> ClaudeUsageData.LimitData {
        let resetsAt = parseResetDate(limit.resetsAt)
        return ClaudeUsageData.LimitData(percentage: limit.utilization, resetsAt: resetsAt)
    }

    private func parseLimitDataOptional(_ limit: ClaudeUsageResponse.LimitUsage?) -> ClaudeUsageData.LimitData? {
        guard let limit = limit else { return nil }
        // Skip if no meaningful data
        if limit.utilization == 0 && limit.resetsAt == nil {
            return nil
        }
        return parseLimitData(limit)
    }

    private func parseResetDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: dateString) {
            // Round to nearest second
            let interval = date.timeIntervalSinceReferenceDate
            let roundedInterval = round(interval)
            return Date(timeIntervalSinceReferenceDate: roundedInterval)
        }

        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }

    private func applyHeaders(to request: inout URLRequest, sessionKey: String) {
        request.setValue("*/*", forHTTPHeaderField: "accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "accept-language")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("web_claude_ai", forHTTPHeaderField: "anthropic-client-platform")
        request.setValue("1.0.0", forHTTPHeaderField: "anthropic-client-version")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", forHTTPHeaderField: "user-agent")
        request.setValue("https://claude.ai", forHTTPHeaderField: "origin")
        request.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "referer")
        request.setValue("empty", forHTTPHeaderField: "sec-fetch-dest")
        request.setValue("cors", forHTTPHeaderField: "sec-fetch-mode")
        request.setValue("same-origin", forHTTPHeaderField: "sec-fetch-site")

        // Build cookie string with session key and optional cf_clearance
        var cookieParts = ["sessionKey=\(sessionKey)"]
        if let cfClearance = cfClearance, !cfClearance.isEmpty {
            cookieParts.append("cf_clearance=\(cfClearance)")
        }
        request.setValue(cookieParts.joined(separator: "; "), forHTTPHeaderField: "Cookie")
    }
}
