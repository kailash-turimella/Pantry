import SwiftUI

/// How urgent an item is, derived purely from its expiry date. Everything in the
/// app that ranks or colours by urgency goes through this type.
enum ExpiryStatus: Comparable, Sendable {
    case expired(daysAgo: Int)
    case today
    case soon(days: Int)      // 1...3 days
    case thisWeek(days: Int)  // 4...7 days
    case fresh(days: Int)     // 8+ days
    case unknown              // no expiry date recorded

    /// Lower sort order == more urgent. Used for the "use soon" ordering.
    var sortRank: Int {
        switch self {
        case .expired: return 0
        case .today: return 1
        case .soon: return 2
        case .thisWeek: return 3
        case .fresh: return 4
        case .unknown: return 5
        }
    }

    static func < (lhs: ExpiryStatus, rhs: ExpiryStatus) -> Bool {
        if lhs.sortRank != rhs.sortRank { return lhs.sortRank < rhs.sortRank }
        return (lhs.daysRemaining ?? .max) < (rhs.daysRemaining ?? .max)
    }

    /// Negative when already expired, nil when there is no date.
    var daysRemaining: Int? {
        switch self {
        case .expired(let daysAgo): return -daysAgo
        case .today: return 0
        case .soon(let days), .thisWeek(let days), .fresh(let days): return days
        case .unknown: return nil
        }
    }

    /// True for anything the "Use Soon" list and notifications should surface.
    var needsAttention: Bool {
        switch self {
        case .expired, .today, .soon, .thisWeek: return true
        case .fresh, .unknown: return false
        }
    }

    var label: String {
        switch self {
        case .expired(let daysAgo):
            return daysAgo == 1 ? "Expired yesterday" : "Expired \(daysAgo)d ago"
        case .today: return "Use today"
        case .soon(let days): return days == 1 ? "1 day left" : "\(days) days left"
        case .thisWeek(let days): return "\(days) days left"
        case .fresh(let days):
            return days > 60 ? "Keeps a while" : "\(days) days left"
        case .unknown: return "No date"
        }
    }

    var tint: Color {
        switch self {
        case .expired: return .red
        case .today: return .orange
        case .soon: return .orange
        case .thisWeek: return .yellow
        case .fresh: return .green
        case .unknown: return .secondary
        }
    }

    /// Days are compared at calendar-day granularity so "expires today" doesn't
    /// flip to "expired" just because the clock passed the time of day it was added.
    static func status(for expiry: Date?, now: Date = Date(), calendar: Calendar = .current) -> ExpiryStatus {
        guard let expiry else { return .unknown }
        let startOfToday = calendar.startOfDay(for: now)
        let startOfExpiry = calendar.startOfDay(for: expiry)
        let days = calendar.dateComponents([.day], from: startOfToday, to: startOfExpiry).day ?? 0

        switch days {
        case ..<0: return .expired(daysAgo: -days)
        case 0: return .today
        case 1...3: return .soon(days: days)
        case 4...7: return .thisWeek(days: days)
        default: return .fresh(days: days)
        }
    }
}
