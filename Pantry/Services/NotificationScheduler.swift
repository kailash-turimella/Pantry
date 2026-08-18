import Foundation
import UserNotifications

/// Local "use this soon" notifications. No server, no push certificates — these
/// are scheduled on-device against each item's expiry date.
enum NotificationScheduler {

    static let leadDaysKey = "notifications.leadDays"
    static let hourKey = "notifications.hour"
    static let enabledKey = "notifications.enabled"

    /// iOS keeps at most 64 pending local notifications per app; stay under it.
    private static let maxScheduled = 48

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// How many days before expiry to warn. Default 2.
    static var leadDays: Int {
        get { UserDefaults.standard.object(forKey: leadDaysKey) as? Int ?? 2 }
        set { UserDefaults.standard.set(newValue, forKey: leadDaysKey) }
    }

    /// Hour of day for the reminder. Default 9am — before you decide what to cook.
    static var hour: Int {
        get { UserDefaults.standard.object(forKey: hourKey) as? Int ?? 9 }
        set { UserDefaults.standard.set(newValue, forKey: hourKey) }
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Rebuilds the whole schedule from the current inventory. Called whenever
    /// items change — cheap, and far simpler than diffing individual requests.
    static func reschedule(for items: [InventoryItem]) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        guard isEnabled else { return }
        guard await authorizationStatus() == .authorized else { return }

        let calendar = Calendar.current
        let now = Date()

        // One notification per day that has something expiring, rather than one
        // per item — otherwise a big shop produces a wall of alerts.
        var byDay: [Date: [InventoryItem]] = [:]
        for item in items {
            guard let expiry = item.expiryDate else { continue }
            guard let warnDate = calendar.date(byAdding: .day, value: -leadDays, to: expiry) else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: warnDate)
            components.hour = hour
            components.minute = 0
            guard let fireDate = calendar.date(from: components), fireDate > now else { continue }

            byDay[fireDate, default: []].append(item)
        }

        let days = byDay.keys.sorted().prefix(maxScheduled)
        for fireDate in days {
            guard let items = byDay[fireDate] else { continue }
            let request = makeRequest(fireDate: fireDate, items: items, calendar: calendar)
            try? await center.add(request)
        }
    }

    private static func makeRequest(
        fireDate: Date,
        items: [InventoryItem],
        calendar: Calendar
    ) -> UNNotificationRequest {
        let names = items.map(\.name)
        let content = UNMutableNotificationContent()

        switch names.count {
        case 1:
            content.title = "Use \(names[0]) soon"
            content.body = "It's due in \(leadDays) day\(leadDays == 1 ? "" : "s"). Tap to see recipes that use it."
        case 2:
            content.title = "2 items to use soon"
            content.body = "\(names[0]) and \(names[1]) are due in \(leadDays) day\(leadDays == 1 ? "" : "s")."
        default:
            content.title = "\(names.count) items to use soon"
            content.body = "\(names.prefix(2).joined(separator: ", ")) and \(names.count - 2) more."
        }
        content.sound = .default

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        return UNNotificationRequest(
            identifier: "expiry-\(Int(fireDate.timeIntervalSince1970))",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }

    static func pendingCount() async -> Int {
        await UNUserNotificationCenter.current().pendingNotificationRequests().count
    }
}
