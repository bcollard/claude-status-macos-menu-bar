import Foundation

/// User-selectable cadence for `/api/oauth/usage` polling.
/// Anthropic rate-limits the endpoint, so options stay >= 1 minute and
/// `.manual` disables auto-polling entirely (the refresh button still
/// honors the throttle).
enum APIRefreshChoice: String, CaseIterable, Identifiable, Sendable {
    case oneMinute     = "1m"
    case fiveMinutes   = "5m"
    case tenMinutes    = "10m"
    case thirtyMinutes = "30m"
    case oneHour       = "1h"
    case manual        = "manual"

    static let `default`: APIRefreshChoice = .fiveMinutes

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .oneMinute:     return 60
        case .fiveMinutes:   return 5 * 60
        case .tenMinutes:    return 10 * 60
        case .thirtyMinutes: return 30 * 60
        case .oneHour:       return 60 * 60
        case .manual:        return .infinity   // skip auto-polling
        }
    }

    var label: String {
        switch self {
        case .oneMinute:     return "Every minute"
        case .fiveMinutes:   return "Every 5 minutes"
        case .tenMinutes:    return "Every 10 minutes"
        case .thirtyMinutes: return "Every 30 minutes"
        case .oneHour:       return "Every hour"
        case .manual:        return "Manual only"
        }
    }
}
