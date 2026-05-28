import Foundation

/// User-selectable cadence for `/api/oauth/usage` polling.
/// Anthropic rate-limits the endpoint aggressively (1/min reliably
/// triggers 429); intervals at or below ~3 min sit close to the cliff
/// and depend on the server-mandated backoff path to recover.
/// `.manual` disables auto-polling entirely (the refresh button still
/// honors server-mandated 429 backoff).
enum APIRefreshChoice: String, CaseIterable, Identifiable, Sendable {
    case twoMinutes    = "2m"
    case threeMinutes  = "3m"
    case fiveMinutes   = "5m"
    case tenMinutes    = "10m"
    case thirtyMinutes = "30m"
    case oneHour       = "1h"
    case manual        = "manual"

    static let `default`: APIRefreshChoice = .fiveMinutes

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .twoMinutes:    return 2 * 60
        case .threeMinutes:  return 3 * 60
        case .fiveMinutes:   return 5 * 60
        case .tenMinutes:    return 10 * 60
        case .thirtyMinutes: return 30 * 60
        case .oneHour:       return 60 * 60
        case .manual:        return .infinity   // skip auto-polling
        }
    }

    var label: String {
        switch self {
        case .twoMinutes:    return "Every 2 minutes"
        case .threeMinutes:  return "Every 3 minutes"
        case .fiveMinutes:   return "Every 5 minutes"
        case .tenMinutes:    return "Every 10 minutes"
        case .thirtyMinutes: return "Every 30 minutes"
        case .oneHour:       return "Every hour"
        case .manual:        return "Manual only"
        }
    }
}
