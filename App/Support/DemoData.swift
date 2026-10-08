import Foundation
import SwiftData

/// Demo mode for screenshots on CI: launch with `-demo` (in-memory store with sample data, no onboarding,
/// no Face ID). Optional: `-startTab home|history|parts|assistant|settings`, `-demoQuestion "…"`,
/// `-settings.language uk|ru|en`, `-settings.theme light|dark|system`.
enum DemoMode {
    #if DEMO_BUILD
    /// Appetize preview build: always in demo mode.
    static let isOn = true
    #else
    static let isOn = ProcessInfo.processInfo.arguments.contains("-demo")
    #endif

    static func value(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var startTab: Router.Tab {
        switch value(after: "-startTab") {
        case "history": return .history
        case "parts": return .parts
        case "assistant": return .assistant
        case "settings": return .settings
        default: return .home
        }
    }

    static var question: String? { value(after: "-demoQuestion") }

    @MainActor
    static func seed(_ context: ModelContext) {
        let lang = L10n.language
        func n(_ uk: String, _ ru: String, _ en: String) -> String {
            lang == "ru" ? ru : (lang == "en" ? en : uk)
        }
        let cal = Calendar.current
        func daysAgo(_ d: Int) -> Date { cal.date(byAdding: .day, value: -d, to: Date())! }

        let car = Car(name: "Škoda Octavia", vin: "TMBJJ7NE8G0123456", avgKmPerMonth: 1500)
        context.insert(car)

        var order = 0
        func item(_ name: String, km: Int? = nil, months: Int? = nil, oem: String? = nil, analogs: [String] = [],
                  aliases: [String] = []) -> Item {
            let i = Item(name: name)
            i.intervalKm = km
            i.intervalMonths = months
            i.oemNumber = oem
            i.analogNumbers = analogs
            i.aliases = aliases
            i.createdAt = Date(timeIntervalSince1970: TimeInterval(order))
            order += 1
            context.insert(i)
            return i
        }

        func fromCatalog(_ key: String, km: Int? = nil, months: Int? = nil, oem: String? = nil,
                         analogs: [String] = []) -> Item {
            let i = item(Catalog.name(key, L10n.assistantLanguage) ?? key, km: km, months: months, oem: oem, analogs: analogs)
            i.catalogKey = key
            return i
        }

        let oil = fromCatalog("engine_oil", km: 10_000, months: 12, oem: "G 052 195 M4",
                              analogs: ["Castrol EDGE 5W-30 LL"])
        let oilFilter = fromCatalog("oil_filter", km: 10_000, months: 12, oem: "03C 115 562",
                                    analogs: ["MANN W 719/45", "BOSCH F 026 407 209"])
        let cabin = fromCatalog("cabin_filter", km: 15_000, months: 12, oem: "5Q0 819 653")
        let air = fromCatalog("air_filter", km: 30_000, months: 24, oem: "5Q0 129 620 B")
        let atf = fromCatalog("dsg_oil", km: 60_000, oem: "G 052 182 A2", analogs: ["Febi 39070"])
        let plugs = fromCatalog("spark_plugs", km: 60_000, oem: "04E 905 612 C")
        let lpg = fromCatalog("lpg_filters", km: 10_000)
        let brake = fromCatalog("brake_fluid", months: 24)
        let belt = fromCatalog("timing_belt", km: 90_000, months: 60)
        let pads = fromCatalog("front_pads", km: 30_000)
        let tires = fromCatalog("seasonal_tires", months: 6)
        // A custom item, shown as typed in every language.
        let washer = item(n("Чистка радіатора", "Чистка радиатора", "Radiator cleaning"), km: 40_000)
        let battery = fromCatalog("battery", months: 60)
        battery.isArchived = true
        _ = washer

        let entries: [(Int, Int, [Item])] = [
            (340, 214_000, [oil, oilFilter, lpg, air]),
            (200, 221_000, [cabin]),
            (120, 224_500, [brake]),
            (700, 196_000, [atf, plugs]),
            (40, 227_000, [oil, oilFilter]),
            (900, 190_500, [belt, battery]),
            (330, 215_000, [pads]),
            (150, 223_000, [tires])
        ]
        for (days, km, items) in entries {
            context.insert(ServiceEntry(date: daysAgo(days), odometerKm: km, items: items))
        }
        context.insert(OdometerReading(date: daysAgo(40), km: 227_000))
        // 20 days ago, so the odometer banner is visible on Home in screenshots.
        context.insert(OdometerReading(date: daysAgo(20), km: 228_100))
        try? context.save()
    }
}
