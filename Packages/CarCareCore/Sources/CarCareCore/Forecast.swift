import Foundation

public enum DueReason: String, Codable, Equatable {
    case time
    case mileage
}

public struct ItemForecast: Equatable {
    public var itemID: UUID
    public var lastDate: Date
    public var lastOdometerKm: Int
    /// Due date by time interval, if the item has intervalMonths.
    public var dueByTime: Date?
    /// Odometer value at which the item is due, if the item has intervalKm.
    public var dueKm: Int?
    /// Projected date when dueKm is reached. Nil when avgKmPerMonth <= 0 and dueKm is not reached yet.
    public var dueByMileage: Date?
    /// The earlier of dueByTime and dueByMileage. Nil only for km-only items with no mileage estimate.
    public var dueDate: Date?
    /// Which limit produced dueDate.
    public var reason: DueReason
    /// Expected odometer at dueDate.
    public var predictedOdometerKm: Int
    public var isOverdue: Bool
    /// The time limit (dueByTime) has passed.
    public var overdueByTime: Bool = false
    /// The odometer has reached dueKm.
    public var overdueByKm: Bool = false

    /// What to show for an overdue item: only the limits that were actually exceeded
    /// (not "today", which dueDate becomes when the km limit is reached).
    public var overdueLimits: (date: Date?, km: Int?) {
        (overdueByTime ? dueByTime : nil, overdueByKm ? dueKm : nil)
    }
}

public enum ItemStatus: Equatable {
    case noInterval
    case noHistory
    case forecast(ItemForecast)

    public var forecast: ItemForecast? {
        if case .forecast(let f) = self { return f }
        return nil
    }
}

public enum ForecastEngine {
    /// Average month length in days used for mileage projections.
    public static let daysPerMonth = 30.4

    /// The latest service entry that contains the item (by date, then odometer).
    public static func lastEntry(for itemID: UUID, entries: [ServiceEntryInfo]) -> ServiceEntryInfo? {
        entries
            .filter { $0.itemIDs.contains(itemID) }
            .max { a, b in
                if a.date != b.date { return a.date < b.date }
                return a.odometerKm < b.odometerKm
            }
    }

    public static func status(
        for item: ItemInfo,
        entries: [ServiceEntryInfo],
        currentOdometerKm: Int?,
        avgKmPerMonth: Double,
        today: Date,
        calendar: Calendar
    ) -> ItemStatus {
        guard item.hasInterval else { return .noInterval }
        switch item.kind {
        case .expiry, .seasonal:
            return dateBasedStatus(for: item, entries: entries, currentOdometerKm: currentOdometerKm,
                                   avgKmPerMonth: avgKmPerMonth, today: today, calendar: calendar)
        case .interval:
            break
        }
        guard let last = lastEntry(for: item.id, entries: entries) else { return .noHistory }

        let todayStart = calendar.startOfDay(for: today)
        let current = max(currentOdometerKm ?? last.odometerKm, 0)
        let kmPerDay = avgKmPerMonth > 0 ? avgKmPerMonth / daysPerMonth : 0

        var dueByTime: Date?
        if let months = item.intervalMonths, months > 0 {
            let lastStart = calendar.startOfDay(for: last.date)
            dueByTime = calendar.date(byAdding: .month, value: months, to: lastStart)
        }

        var dueKm: Int?
        var dueByMileage: Date?
        if let interval = item.intervalKm, interval > 0 {
            let km = last.odometerKm + interval
            dueKm = km
            let remaining = max(0, km - current)
            if remaining == 0 {
                dueByMileage = todayStart
            } else if kmPerDay > 0 {
                // Small epsilon: 3040 / 30.4 is 100.00000000000001 in floating point.
                let days = Int((Double(remaining) / kmPerDay + 1e-6).rounded(.down))
                dueByMileage = calendar.date(byAdding: .day, value: days, to: todayStart)
            }
        }

        let dueDate: Date?
        let reason: DueReason
        switch (dueByTime, dueByMileage) {
        case let (t?, m?):
            if m < t { dueDate = m; reason = .mileage } else { dueDate = t; reason = .time }
        case let (t?, nil):
            dueDate = t; reason = .time
        case let (nil, m?):
            dueDate = m; reason = .mileage
        case (nil, nil):
            dueDate = nil; reason = .mileage
        }

        let predicted: Int
        if reason == .mileage, let km = dueKm {
            predicted = max(km, current)
        } else if let d = dueDate, d > todayStart {
            let days = calendar.dateComponents([.day], from: todayStart, to: d).day ?? 0
            predicted = current + Int((Double(days) * kmPerDay).rounded())
        } else {
            predicted = current
        }

        let overdueByTime = dueByTime.map { calendar.startOfDay(for: $0) < todayStart } ?? false
        let overdueByKm = dueKm.map { current >= $0 } ?? false
        let overdue = overdueByTime || overdueByKm

        return .forecast(ItemForecast(
            itemID: item.id,
            lastDate: last.date,
            lastOdometerKm: last.odometerKm,
            dueByTime: dueByTime,
            dueKm: dueKm,
            dueByMileage: dueByMileage,
            dueDate: dueDate,
            reason: reason,
            predictedOdometerKm: predicted,
            isOverdue: overdue,
            overdueByTime: overdueByTime,
            overdueByKm: overdueByKm
        ))
    }

}

extension ForecastEngine {
    /// Expiry items: due on `validUntil`. Seasonal items: due on the 1st of the first season month after the month
    /// of the last service (or, with no records, the next season month from now); overdue once that month has
    /// passed without a record. Both are time-based: no km limit.
    static func dateBasedStatus(for item: ItemInfo, entries: [ServiceEntryInfo], currentOdometerKm: Int?,
                                avgKmPerMonth: Double, today: Date, calendar: Calendar) -> ItemStatus {
        let todayStart = calendar.startOfDay(for: today)
        let last = lastEntry(for: item.id, entries: entries)
        let current = max(currentOdometerKm ?? last?.odometerKm ?? 0, 0)
        let kmPerDay = avgKmPerMonth > 0 ? avgKmPerMonth / daysPerMonth : 0

        let due: Date
        let overdue: Bool
        switch item.kind {
        case .expiry:
            guard let until = item.validUntil else { return .noHistory }
            due = calendar.startOfDay(for: until)
            overdue = due < todayStart
        case .seasonal:
            guard let next = nextSeasonStart(months: item.seasonMonths, after: last?.date, today: today,
                                             calendar: calendar) else { return .noInterval }
            due = next
            let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: todayStart))!
            overdue = due < thisMonth
        case .interval:
            return .noInterval
        }

        var predicted = current
        if due > todayStart {
            let days = calendar.dateComponents([.day], from: todayStart, to: due).day ?? 0
            predicted = current + Int((Double(days) * kmPerDay).rounded())
        }
        return .forecast(ItemForecast(
            itemID: item.id,
            lastDate: last?.date ?? todayStart,
            lastOdometerKm: last?.odometerKm ?? current,
            dueByTime: due,
            dueKm: nil,
            dueByMileage: nil,
            dueDate: due,
            reason: .time,
            predictedOdometerKm: predicted,
            isOverdue: overdue,
            overdueByTime: overdue,
            overdueByKm: false
        ))
    }

    /// First day of the first season month strictly after the month of `after`,
    /// or (no record) the first season month starting this month or later.
    public static func nextSeasonStart(months: [Int], after: Date?, today: Date, calendar: Calendar) -> Date? {
        let valid = Set(months.filter { (1...12).contains($0) })
        guard !valid.isEmpty else { return nil }
        func monthStart(_ d: Date) -> Date { calendar.date(from: calendar.dateComponents([.year, .month], from: d))! }
        var cursor: Date
        if let after {
            cursor = calendar.date(byAdding: .month, value: 1, to: monthStart(after))!
        } else {
            cursor = monthStart(today)
        }
        for _ in 0..<36 {
            if valid.contains(calendar.component(.month, from: cursor)) { return cursor }
            cursor = calendar.date(byAdding: .month, value: 1, to: cursor)!
        }
        return nil
    }
}

extension ItemForecast {
    /// Whole days until the due date (0 when today or overdue).
    public func daysLeft(today: Date, calendar: Calendar) -> Int? {
        guard let d = dueDate else { return nil }
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: today),
                                              to: calendar.startOfDay(for: d)).day ?? 0)
    }
}
