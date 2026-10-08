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
    /// true: the "lead time" reminder before the due day; false: the reminder on the due day itself.
    public var isAdvance: Bool
}

public enum ReminderPlanner {
    /// iOS keeps at most 64 pending local notifications; leave room for odometer nudges.
    public static let maxReminders = 50
    /// Local time of every notification (the device's current time zone).
    public static let fireHour = 11

    /// For every upcoming due day: one reminder `leadTime` before (if that moment is still ahead) and one on
    /// the day itself. Overdue items get none (Home shows them). The soonest 50 notifications are kept.
    public static func plan(statuses: [UUID: ItemStatus], items: [ItemInfo], leadTime: ReminderLeadTime,
                            now: Date, calendar: Calendar, hour: Int = fireHour,
                            minute: Int = 0) -> [PlannedReminder] {
        let order = Dictionary(items.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        var byDay: [Date: [UUID]] = [:]
        for status in statuses.values {
            guard let f = status.forecast, !f.isOverdue, let due = f.dueDate else { continue }
            byDay[calendar.startOfDay(for: due), default: []].append(f.itemID)
        }

        var result: [PlannedReminder] = []
        for day in byDay.keys.sorted() {
            guard let dueFire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { continue }
            let ids = byDay[day]!.sorted { (order[$0] ?? 0) < (order[$1] ?? 0) }
            let c = calendar.dateComponents([.year, .month, .day], from: day)
            let base = String(format: "due-%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            if leadTime.days > 0,
               let advance = calendar.date(byAdding: .day, value: -leadTime.days, to: dueFire), advance > now {
                result.append(PlannedReminder(identifier: base + "-advance", fireDate: advance, dueDay: day,
                                              itemIDs: ids, isAdvance: true))
            }
            if dueFire > now {
                result.append(PlannedReminder(identifier: base, fireDate: dueFire, dueDay: day,
                                              itemIDs: ids, isAdvance: false))
            }
        }
        return Array(result.sorted { $0.fireDate < $1.fireDate }.prefix(maxReminders))
    }
}
