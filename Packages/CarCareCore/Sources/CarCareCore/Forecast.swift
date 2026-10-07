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

    /// Statuses for every item in the snapshot, keyed by item id.
    /// Statuses for every active (not archived) item, keyed by item id.
    public static func statuses(for snapshot: DataSnapshot, today: Date, calendar: Calendar) -> [UUID: ItemStatus] {
        let current = OdometerRules.current(readings: snapshot.odometerReadings, entries: snapshot.entries,
                                            calendar: calendar)?.km
        let avg = snapshot.car?.avgKmPerMonth ?? 0
        var result: [UUID: ItemStatus] = [:]
        for item in snapshot.activeItems {
            result[item.id] = status(for: item, entries: snapshot.entries, currentOdometerKm: current,
                                     avgKmPerMonth: avg, today: today, calendar: calendar)
        }
        return result
    }
}

/// Home screen grouping: overdue items first, then upcoming items grouped by due day.
/// With a horizon, only items due within 12 months OR within 15 000 km are "upcoming"; the rest is "later".
public struct ForecastGroups: Equatable {
    public struct DayGroup: Equatable {
        public var day: Date
        public var forecasts: [ItemForecast]
    }

    public static let horizonMonths = 12
    public static let horizonKm = 15_000

    public var overdue: [ItemForecast]
    public var upcoming: [DayGroup]
    /// Items with a km interval but no date estimate (avgKmPerMonth <= 0).
    public var undated: [ItemForecast]
    /// Beyond the horizon, grouped by day like `upcoming`.
    public var later: [DayGroup]

    public static func make(from statuses: [UUID: ItemStatus], calendar: Calendar,
                            today: Date? = nil, currentOdometerKm: Int? = nil) -> ForecastGroups {
        let all = statuses.values.compactMap { $0.forecast }
        let overdue = all.filter { $0.isOverdue }
            .sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
        let dated = all.filter { !$0.isOverdue && $0.dueDate != nil }
        let undated = all.filter { !$0.isOverdue && $0.dueDate == nil }
            .sorted { ($0.dueKm ?? 0) < ($1.dueKm ?? 0) }

        func withinHorizon(_ f: ItemForecast) -> Bool {
            guard let today else { return true }
            if let limit = calendar.date(byAdding: .month, value: horizonMonths, to: calendar.startOfDay(for: today)),
               let due = f.dueDate, due <= limit { return true }
            if let current = currentOdometerKm {
                let kmAtDue = f.dueKm ?? f.predictedOdometerKm
                if kmAtDue <= current + horizonKm { return true }
            }
            return false
        }

        func grouped(_ list: [ItemForecast]) -> [DayGroup] {
            var byDay: [Date: [ItemForecast]] = [:]
            for f in list {
                byDay[calendar.startOfDay(for: f.dueDate!), default: []].append(f)
            }
            return byDay.keys.sorted().map { day in
                DayGroup(day: day, forecasts: byDay[day]!.sorted { $0.predictedOdometerKm < $1.predictedOdometerKm })
            }
        }

        return ForecastGroups(overdue: overdue, upcoming: grouped(dated.filter(withinHorizon)), undated: undated,
                              later: grouped(dated.filter { !withinHorizon($0) }))
    }
}
