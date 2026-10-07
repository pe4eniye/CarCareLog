import Foundation

public enum OdometerRules {
    public static let nudgeIntervalDays = 14

    /// The latest reading (by date, then by km).
    public static func current(readings: [OdometerReadingInfo]) -> OdometerReadingInfo? {
        readings.max { a, b in
            if a.date != b.date { return a.date < b.date }
            return a.km < b.km
        }
    }

    /// True when the new value is lower than the current odometer. The UI warns but does not block.
    public static func isLowerThanCurrent(_ km: Int, readings: [OdometerReadingInfo]) -> Bool {
        guard let cur = current(readings: readings) else { return false }
        return km < cur.km
    }

    /// A service entry with a higher odometer than the current one also creates an OdometerReading.
    public static func serviceEntryShouldAddReading(entryKm: Int, readings: [OdometerReadingInfo]) -> Bool {
        guard let cur = current(readings: readings) else { return true }
        return entryKm > cur.km
    }

    /// The Home banner shows when 14+ days passed since the last reading, or when there is none.
    public static func needsNudge(readings: [OdometerReadingInfo], now: Date, calendar: Calendar) -> Bool {
        guard let last = current(readings: readings) else { return true }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last.date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        return days >= nudgeIntervalDays
    }

    /// Future 09:00 dates for odometer nudges: every 14 days after the last reading.
    public static func nudgeDates(readings: [OdometerReadingInfo], now: Date, calendar: Calendar,
                                  count: Int = 3, hour: Int = 9) -> [Date] {
        let base = current(readings: readings).map { calendar.startOfDay(for: $0.date) }
            ?? calendar.startOfDay(for: now)
        var result: [Date] = []
        var step = 1
        while result.count < count && step < 1000 {
            if let day = calendar.date(byAdding: .day, value: nudgeIntervalDays * step, to: base),
               let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day),
               fire > now {
                result.append(fire)
            }
            step += 1
        }
        return result
    }
}

public enum ValidationRules {
    public enum EntryProblem: Equatable {
        case dateInFuture
        case noItems
        case negativeOdometer
    }

    public static func validateEntry(date: Date, odometerKm: Int, itemCount: Int,
                                     now: Date, calendar: Calendar) -> [EntryProblem] {
        var problems: [EntryProblem] = []
        if calendar.startOfDay(for: date) > calendar.startOfDay(for: now) { problems.append(.dateInFuture) }
        if itemCount == 0 { problems.append(.noItems) }
        if odometerKm < 0 { problems.append(.negativeOdometer) }
        return problems
    }

    /// Soft warning only: a VIN is normally 17 characters.
    public static func vinLooksWrong(_ vin: String?) -> Bool {
        guard let v = vin?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return false }
        return v.count != 17
    }
}
