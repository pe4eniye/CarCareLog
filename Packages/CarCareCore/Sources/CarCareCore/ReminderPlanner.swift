import Foundation

public enum ReminderLeadTime: Int, Codable, CaseIterable, Identifiable {
    case sameDay = 0
    case oneWeek = 7
    case twoWeeks = 14
    case threeWeeks = 21
    case oneMonth = 30

    public var id: Int { rawValue }
    public var days: Int { rawValue }
}

/// One local notification: all items due on the same day are grouped together.
public struct PlannedReminder: Equatable {
    /// Stable identifier, so rescheduling replaces instead of duplicating.
    public var identifier: String
    public var fireDate: Date
    public var dueDay: Date
    public var itemIDs: [UUID]
}

public enum ReminderPlanner {
    /// iOS keeps at most 64 pending local notifications; leave room for odometer nudges.
    public static let maxItemReminders = 50
    public static let fireHour = 9

    public static func plan(statuses: [UUID: ItemStatus], items: [ItemInfo], leadTime: ReminderLeadTime,
                            now: Date, calendar: Calendar) -> [PlannedReminder] {
        let order = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($1.id, $0) })
        var byDay: [Date: [UUID]] = [:]
        for status in statuses.values {
            guard let f = status.forecast, !f.isOverdue, let due = f.dueDate else { continue }
            byDay[calendar.startOfDay(for: due), default: []].append(f.itemID)
        }

        var result: [PlannedReminder] = []
        for day in byDay.keys.sorted() {
            guard let dueFire = calendar.date(bySettingHour: fireHour, minute: 0, second: 0, of: day) else { continue }
            var fire = calendar.date(byAdding: .day, value: -leadTime.days, to: dueFire) ?? dueFire
            // Lead time already passed but the due day is still ahead: remind on the due day itself.
            if fire <= now { fire = dueFire }
            guard fire > now else { continue }
            let ids = byDay[day]!.sorted { (order[$0] ?? 0) < (order[$1] ?? 0) }
            let c = calendar.dateComponents([.year, .month, .day], from: day)
            let identifier = String(format: "due-%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            result.append(PlannedReminder(identifier: identifier, fireDate: fire, dueDay: day, itemIDs: ids))
            if result.count >= maxItemReminders { break }
        }
        return result
    }
}
