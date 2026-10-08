import Foundation

extension ForecastEngine {
    /// Statuses for every active (not archived) item, keyed by item id.
    /// Uses the automatic km/month estimate when there is enough data (see `MileageEstimator`).
    public static func statuses(for snapshot: DataSnapshot, today: Date, calendar: Calendar) -> [UUID: ItemStatus] {
        let current = OdometerRules.current(readings: snapshot.odometerReadings, entries: snapshot.entries,
                                            calendar: calendar)?.km
        let avg = MileageEstimator.estimate(snapshot: snapshot, today: today, calendar: calendar).value
        var result: [UUID: ItemStatus] = [:]
        for item in snapshot.activeItems {
            result[item.id] = status(for: item, entries: snapshot.entries, currentOdometerKm: current,
                                     avgKmPerMonth: avg, today: today, calendar: calendar)
        }
        return result
    }

    /// Schedule order: overdue first (most overdue on top), then by expected date (a km limit is turned into a
    /// date with the average km/month and the earlier limit wins), then km-only items without a date, then items
    /// with no forecast (no interval or no records). Ties by name.
    public static func urgencySorted(_ items: [ItemInfo], statuses: [UUID: ItemStatus]) -> [ItemInfo] {
        func rank(_ item: ItemInfo) -> (Int, Double, String) {
            let name = item.name.lowercased()
            guard let f = statuses[item.id]?.forecast else { return (3, 0, name) }
            if f.isOverdue { return (0, (f.dueDate ?? .distantPast).timeIntervalSince1970, name) }
            if let d = f.dueDate { return (1, d.timeIntervalSince1970, name) }
            return (2, Double(f.dueKm ?? Int.max), name)
        }
        return items.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra.0 != rb.0 { return ra.0 < rb.0 }
            if ra.1 != rb.1 { return ra.1 < rb.1 }
            return ra.2 < rb.2
        }
    }
}

/// Traffic-light status shown on Home cards and in the schedule.
public enum Urgency: Int, Comparable {
    /// Green: more than 2 months to go.
    case ok = 0
    /// Yellow: 2 months or less.
    case soon = 1
    /// Red.
    case overdue = 2

    public static func < (a: Urgency, b: Urgency) -> Bool { a.rawValue < b.rawValue }

    public static let soonMonths = 2
    /// For km-only items without a date estimate.
    public static let soonKmWithoutDate = 3_000
}

extension ItemForecast {
    public func urgency(today: Date, calendar: Calendar, currentOdometerKm: Int?) -> Urgency {
        if isOverdue { return .overdue }
        if let d = dueDate {
            let limit = calendar.date(byAdding: .month, value: Urgency.soonMonths, to: calendar.startOfDay(for: today))!
            return d <= limit ? .soon : .ok
        }
        if let km = dueKm, let current = currentOdometerKm, km - current <= Urgency.soonKmWithoutDate { return .soon }
        return .ok
    }

    /// Kilometres left until the expected replacement ("in 7 900 km").
    public func kmLeft(currentOdometerKm: Int?) -> Int? {
        guard let current = currentOdometerKm else { return nil }
        let target = reason == .mileage ? (dueKm ?? predictedOdometerKm) : predictedOdometerKm
        return max(0, target - current)
    }
}

/// Home screen: overdue items first, then upcoming items grouped by calendar month.
/// With a horizon, only items due within 12 months OR within 15 000 km are "upcoming"; the rest is "later".
public struct ForecastGroups: Equatable {
    public struct MonthGroup: Equatable {
        /// First day of the month.
        public var month: Date
        /// Sorted by expected date, then by odometer.
        public var forecasts: [ItemForecast]
    }

    public static let horizonMonths = 12
    public static let horizonKm = 15_000

    public var overdue: [ItemForecast]
    public var upcoming: [MonthGroup]
    /// Items with a km interval but no date estimate (avgKmPerMonth <= 0).
    public var undated: [ItemForecast]
    /// Beyond the horizon, grouped by month like `upcoming`.
    public var later: [MonthGroup]

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

        func grouped(_ list: [ItemForecast]) -> [MonthGroup] {
            var byMonth: [Date: [ItemForecast]] = [:]
            for f in list {
                let c = calendar.dateComponents([.year, .month], from: f.dueDate!)
                byMonth[calendar.date(from: c)!, default: []].append(f)
            }
            return byMonth.keys.sorted().map { month in
                MonthGroup(month: month, forecasts: byMonth[month]!.sorted { a, b in
                    if a.dueDate != b.dueDate { return a.dueDate! < b.dueDate! }
                    return a.predictedOdometerKm < b.predictedOdometerKm
                })
            }
        }

        return ForecastGroups(overdue: overdue, upcoming: grouped(dated.filter(withinHorizon)), undated: undated,
                              later: grouped(dated.filter { !withinHorizon($0) }))
    }
}

/// Average km per month from the user's own data: odometer updates and service entries of the last 6 months.
/// Until those points span at least 2 months, the manually entered value is used.
public enum MileageEstimator {
    public static let windowDays = 183
    public static let minSpanDays = 60

    public struct Estimate: Equatable {
        public var value: Double
        public var isAutomatic: Bool
        /// Days covered by the data used (0 for the manual value).
        public var spanDays: Int
    }

    public static func estimate(snapshot: DataSnapshot, today: Date, calendar: Calendar) -> Estimate {
        let manual = Estimate(value: snapshot.car?.avgKmPerMonth ?? 0, isAutomatic: false, spanDays: 0)
        let todayStart = calendar.startOfDay(for: today)
        guard let from = calendar.date(byAdding: .day, value: -windowDays, to: todayStart) else { return manual }
        let points = OdometerRules.points(readings: snapshot.odometerReadings, entries: snapshot.entries)
            .filter { calendar.startOfDay(for: $0.date) >= from && calendar.startOfDay(for: $0.date) <= todayStart }
        guard points.count >= 2,
              let first = points.min(by: { a, b in a.date != b.date ? a.date < b.date : a.km < b.km }),
              let last = OdometerRules.current(readings: points, entries: [], calendar: calendar) else { return manual }
        let span = OdometerRules.daysSince(first.date, now: last.date, calendar: calendar)
        guard span >= minSpanDays, last.km > first.km else { return manual }
        let perMonth = Double(last.km - first.km) / Double(span) * ForecastEngine.daysPerMonth
        let clamped = min(max(perMonth.rounded(), Double(Limits.avgKmPerMonth.lowerBound)),
                          Double(Limits.avgKmPerMonth.upperBound))
        return Estimate(value: clamped, isAutomatic: true, spanDays: span)
    }
}

extension ForecastEngine {
    /// Share of the interval already used, 0…1 (1 when overdue), for the wear rings.
    /// Time share = elapsed / (due − last); km share = driven / interval km; the larger one counts.
    /// nil when there is nothing to measure from (e.g. an expiry item without any record).
    public static func wear(item: ItemInfo, forecast f: ItemForecast, entries: [ServiceEntryInfo],
                            currentOdometerKm: Int?, today: Date) -> Double? {
        if f.isOverdue { return 1 }
        guard lastEntry(for: item.id, entries: entries) != nil else { return nil }
        var shares: [Double] = []
        if let due = f.dueByTime {
            let total = due.timeIntervalSince(f.lastDate)
            if total > 0 { shares.append(today.timeIntervalSince(f.lastDate) / total) }
        }
        if let km = item.intervalKm, km > 0, f.dueKm != nil, let current = currentOdometerKm {
            shares.append(Double(current - f.lastOdometerKm) / Double(km))
        }
        guard let share = shares.max() else { return nil }
        return min(max(share, 0), 1)
    }
}
