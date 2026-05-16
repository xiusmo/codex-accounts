import Foundation

/// Response body from `GET https://chatgpt.com/backend-api/wham/usage`.
/// Matches codex's `RateLimitStatusPayload` (codex-rs/codex-backend-openapi-models).
struct UsagePayload: Codable {
    var planType: String?
    var rateLimit: RateLimitDetails?
    var credits: CreditDetails?
    var additionalRateLimits: [AdditionalRateLimitDetails]?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
        case additionalRateLimits = "additional_rate_limits"
    }
}

struct AdditionalRateLimitDetails: Codable {
    var limitName: String?
    var meteredFeature: String?
    var rateLimit: RateLimitDetails?

    enum CodingKeys: String, CodingKey {
        case limitName = "limit_name"
        case meteredFeature = "metered_feature"
        case rateLimit = "rate_limit"
    }
}

struct RateLimitDetails: Codable {
    var allowed: Bool?
    var limitReached: Bool?
    var primaryWindow: RateLimitWindow?
    var secondaryWindow: RateLimitWindow?

    enum CodingKeys: String, CodingKey {
        case allowed
        case limitReached = "limit_reached"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

struct RateLimitWindow: Codable {
    /// Codex backend declares this as i32 in OpenAPI but uses f64 elsewhere.
    /// Decode as Double for safety.
    var usedPercent: Double
    var limitWindowSeconds: Int?
    var resetAfterSeconds: Int?
    var resetAt: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAfterSeconds = "reset_after_seconds"
        case resetAt = "reset_at"
    }
}

struct CreditDetails: Codable {
    var hasCredits: Bool?
    var unlimited: Bool?
    var balance: String?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }
}
