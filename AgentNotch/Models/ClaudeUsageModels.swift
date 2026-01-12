//
//  ClaudeUsageModels.swift
//  AgentNotch
//
//  Models for Claude API usage quota tracking
//

import Foundation

// MARK: - API Response Models

/// Response from /api/organizations endpoint
struct ClaudeOrganization: Codable {
    let id: Int
    let uuid: String
    let name: String
    let createdAt: String?
    let updatedAt: String?
    let capabilities: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case uuid
        case name
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case capabilities
    }
}

/// Response from /api/organizations/{orgId}/usage endpoint
struct ClaudeUsageResponse: Codable {
    let fiveHour: LimitUsage
    let sevenDay: LimitUsage?
    let sevenDayOauthApps: LimitUsage?
    let sevenDayOpus: LimitUsage?
    let sevenDaySonnet: LimitUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOauthApps = "seven_day_oauth_apps"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }

    struct LimitUsage: Codable {
        let utilization: Double  // 0-100 percentage
        let resetsAt: String?    // ISO 8601 format

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }
}

/// Response from /api/organizations/{orgId}/overage_spend_limit endpoint
struct ClaudeExtraUsageResponse: Codable {
    let type: String
    let spendLimitCurrency: String
    let spendLimitAmountCents: Int?
    let balanceCents: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case spendLimitCurrency = "spend_limit_currency"
        case spendLimitAmountCents = "spend_limit_amount_cents"
        case balanceCents = "balance_cents"
    }
}

/// Error response from API
struct ClaudeAPIErrorResponse: Codable {
    let error: ErrorDetail

    struct ErrorDetail: Codable {
        let type: String
        let message: String
    }
}

// MARK: - App Data Models

/// Parsed usage data for display
struct ClaudeUsageData: Equatable {
    let fiveHour: LimitData?
    let sevenDay: LimitData?
    let opus: LimitData?
    let sonnet: LimitData?
    let extraUsage: ExtraUsageData?
    let fetchedAt: Date

    static let empty = ClaudeUsageData(
        fiveHour: nil,
        sevenDay: nil,
        opus: nil,
        sonnet: nil,
        extraUsage: nil,
        fetchedAt: Date()
    )

    struct LimitData: Equatable {
        let percentage: Double       // 0-100
        let resetsAt: Date?

        /// Time remaining until reset
        var resetsIn: TimeInterval? {
            guard let resetsAt = resetsAt else { return nil }
            return resetsAt.timeIntervalSinceNow
        }

        /// Formatted remaining time (e.g., "2h 30m", "3d 12h")
        var formattedRemaining: String {
            guard let seconds = resetsIn, seconds > 0 else { return "—" }

            let hours = Int(seconds) / 3600
            let minutes = (Int(seconds) % 3600) / 60

            if hours >= 24 {
                let days = hours / 24
                let remainingHours = hours % 24
                return "\(days)d \(remainingHours)h"
            } else if hours > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(minutes)m"
            }
        }

        /// Compact percentage string
        var formattedPercentage: String {
            return "\(Int(percentage.rounded()))%"
        }

        /// Color based on usage level
        var usageLevel: UsageLevel {
            switch percentage {
            case 0..<50: return .low
            case 50..<80: return .medium
            default: return .high
            }
        }
    }

    struct ExtraUsageData: Equatable {
        let enabled: Bool
        let usedDollars: Double?
        let limitDollars: Double?
        let currency: String

        var percentage: Double? {
            guard let used = usedDollars, let limit = limitDollars, limit > 0 else {
                return nil
            }
            return (used / limit) * 100
        }

        var formattedUsed: String {
            guard let used = usedDollars else { return "—" }
            return String(format: "$%.2f", used)
        }

        var formattedLimit: String {
            guard let limit = limitDollars else { return "—" }
            return String(format: "$%.2f", limit)
        }
    }
}

// MARK: - Usage Level

enum UsageLevel {
    case low      // 0-50%: green
    case medium   // 50-80%: orange
    case high     // 80-100%: red
}

// MARK: - Refresh Mode

enum UsageRefreshMode: String, CaseIterable, Identifiable {
    case smart = "Smart"
    case fixed = "Fixed"

    var id: String { rawValue }
}

enum UsageRefreshInterval: Int, CaseIterable, Identifiable {
    case oneMinute = 60
    case threeMinutes = 180
    case fiveMinutes = 300
    case tenMinutes = 600

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .oneMinute: return "1 minute"
        case .threeMinutes: return "3 minutes"
        case .fiveMinutes: return "5 minutes"
        case .tenMinutes: return "10 minutes"
        }
    }
}

/// Smart monitoring modes (adaptive based on activity)
enum UsageMonitoringMode: String {
    case active = "active"           // 1 minute
    case idleShort = "idle_short"    // 3 minutes
    case idleMedium = "idle_medium"  // 5 minutes
    case idleLong = "idle_long"      // 10 minutes

    var interval: TimeInterval {
        switch self {
        case .active: return 60
        case .idleShort: return 180
        case .idleMedium: return 300
        case .idleLong: return 600
        }
    }
}

// MARK: - Errors

enum ClaudeUsageError: LocalizedError {
    case invalidURL
    case noData
    case sessionExpired
    case cloudflareBlocked
    case noCredentials
    case networkError(Error)
    case decodingError(Error)
    case unauthorized
    case rateLimited
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .noData:
            return "No data received"
        case .sessionExpired:
            return "Session expired. Please update your session key."
        case .cloudflareBlocked:
            return "Request blocked by Cloudflare"
        case .noCredentials:
            return "Missing session key or organization ID"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .unauthorized:
            return "Invalid session key"
        case .rateLimited:
            return "Too many requests. Please wait."
        case .httpError(let code):
            return "HTTP error: \(code)"
        }
    }
}
