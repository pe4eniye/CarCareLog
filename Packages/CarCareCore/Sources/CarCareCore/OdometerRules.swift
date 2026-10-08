import Foundation

/// The current odometer is derived from two sources: odometer readings the user entered and the odometer
/// of service entries. Nothing is copied between them, so editing or deleting an entry immediately gives
/// the right current value everywhere.
public enum OdometerRules {
    public static let nudgeIntervalDays = 14

    /// All known odometer points: readings plus service entries.
    public static func points(readings: [OdometerReadingInfo], entries: [ServiceEntryInfo]) -> [OdometerReadingInfo] {
        readings + entries.map { OdometerReadingInfo(id: $0.id, date: $0.date, km: $0.odometerKm) }
    }

    /// The latest point by calendar day; within the same day the highest km wins
    /// (an entry dated today at 00:00 and a reading from this morning are "the same day").
    public static func current(readings: [OdometerReadingInfo], entries: [ServiceEntryInfo] = [],
                               calendar: Calendar = .current) -> OdometerReadingInfo? {
        points(readings: readings, entries: entries).max { a, b in
            let da = calendar.startOfDay(for: a.date), db = calendar.startOfDay(for: b.date)
            if da != db { return da < db }
            return a.km < b.km
        }
    }

    /// True when the new value is lower than the current odometer. The UI warns but does not block.
    public static func isLowerThanCurrent(_ km: Int, readings: [OdometerReadingInfo],
                                          entries: [ServiceEntryInfo] = [], calendar: Calendar = .current) -> Bool {
        guard let cur = current(readings: readings, entries: entries, calendar: calendar) else { return false }
        return km < cur.km
    }

    /// Date of the last odometer update (reading or service entry).
    public static func lastUpdate(readings: [OdometerReadingInfo], entries: [ServiceEntryInfo],
                                  calendar: Calendar = .current) -> Date? {
        current(readings: readings, entries: entries, calendar: calendar)?.date
    }

    /// The Home banner shows when 14+ days passed since the last update, or when there is none.
    public static func needsNudge(readings: [OdometerReadingInfo], entries: [ServiceEntryInfo] = [],
                                  now: Date, calendar: Calendar, intervalDays: Int = nudgeIntervalDays) -> Bool {
        guard intervalDays > 0 else { return false } // reminders turned off
        guard let last = lastUpdate(readings: readings, entries: entries, calendar: calendar) else { return true }
        return daysSince(last, now: now, calendar: calendar) >= intervalDays
    }

    public static func daysSince(_ date: Date, now: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
    }

    /// Future reminder dates for odometer nudges: every 14 days after the last update, at `hour` local time.
    public static func nudgeDates(readings: [OdometerReadingInfo], entries: [ServiceEntryInfo] = [], now: Date,
                                  calendar: Calendar, count: Int = 3, hour: Int = ReminderPlanner.fireHour,
                                  minute: Int = 0, intervalDays: Int = nudgeIntervalDays) -> [Date] {
        guard intervalDays > 0 else { return [] }
        let base = lastUpdate(readings: readings, entries: entries, calendar: calendar)
            .map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: now)
        var result: [Date] = []
        var step = 1
        while result.count < count && step < 1000 {
            if let day = calendar.date(byAdding: .day, value: intervalDays * step, to: base),
               let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
               fire > now {
                result.append(fire)
            }
            step += 1
        }
        return result
    }
}
