import Foundation
@testable import CarCareCore

enum TS {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    static func d(_ y: Int, _ m: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: day, hour: hour))!
    }

    /// Today in all tests: 7 October 2026.
    static let today = d(2026, 10, 7, 12)

    /// Replaces non-breaking spaces so expectations stay readable.
    static func plain(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}

/// A realistic garage: avg 3040 km/month = exactly 100 km/day, current odometer 228 000.
struct Garage {
    let engineOil = ItemInfo(name: "Моторне масло", intervalKm: 10_000, intervalMonths: 12,
                             oemNumber: "06L 115 562", analogNumbers: ["W 719/45"])
    let oilFilter = ItemInfo(name: "Масляний фільтр", intervalKm: 10_000)
    let atf = ItemInfo(name: "Масло АКП", intervalKm: 60_000, oemNumber: "G 055 025 A2",
                       analogNumbers: ["ATF-1234", "Mobil ATF 3309"])
    let cabin = ItemInfo(name: "Фільтр салону", intervalKm: 15_000, intervalMonths: 12)
    let plugs = ItemInfo(name: "Свічки запалювання", aliases: ["свечи"], intervalKm: 60_000)
    let lpg = ItemInfo(name: "Фільтри ГБО", intervalKm: 10_000)
    let airFilter = ItemInfo(name: "Повітряний фільтр", intervalKm: 30_000)
    let brakeFluid = ItemInfo(name: "Гальмівна рідина", intervalMonths: 24)

    var items: [ItemInfo] { [engineOil, oilFilter, atf, cabin, plugs, lpg, airFilter, brakeFluid] }

    var entries: [ServiceEntryInfo] {
        [
            ServiceEntryInfo(date: TS.d(2025, 11, 3), odometerKm: 220_000,
                             itemIDs: [engineOil.id, oilFilter.id, lpg.id]),
            ServiceEntryInfo(date: TS.d(2024, 6, 10), odometerKm: 190_000, itemIDs: [atf.id, plugs.id]),
            ServiceEntryInfo(date: TS.d(2026, 3, 15), odometerKm: 224_000, itemIDs: [cabin.id]),
            ServiceEntryInfo(date: TS.d(2026, 8, 20), odometerKm: 227_000, itemIDs: [brakeFluid.id])
        ]
    }

    var readings: [OdometerReadingInfo] {
        [
            OdometerReadingInfo(date: TS.d(2026, 8, 20), km: 227_000),
            OdometerReadingInfo(date: TS.d(2026, 10, 1), km: 228_000)
        ]
    }

    var snapshot: DataSnapshot {
        DataSnapshot(car: CarInfo(make: "Skoda", model: "Octavia", year: 2015, avgKmPerMonth: 3040),
                     items: items, entries: entries, odometerReadings: readings)
    }

    func context(fallback: AssistantLanguage = .uk) -> AssistantContext {
        AssistantContext(snapshot: snapshot, today: TS.today, calendar: TS.calendar, fallbackLanguage: fallback)
    }
}
