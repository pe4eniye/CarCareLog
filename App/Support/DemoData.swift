import Foundation
import SwiftData
import CarCareCore

/// Demo mode for screenshots on CI: launch with `-demo` (in-memory store with sample data, no onboarding,
/// no Face ID). Optional: `-startTab home|history|parts|expenses|assistant|settings` (settings opens the sheet), `-demoQuestion "…"`,
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
        case "expenses": return .expenses
        default: return .home
        }
    }

    static var question: String? { value(after: "-demoQuestion") }

    /// For the screenshot tour: `-demoSheet odometer|log|addItems|newItem|entry|item:<catalogKey>` opens that form
    /// right after the sample data is in place.
    @MainActor
    static func openSheet(_ context: ModelContext, router: Router) {
        guard let value = value(after: "-demoSheet") else { return }
        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        func item(_ key: String) -> Item? { items.first { $0.catalogKey == key } }
        switch value {
        case "odometer": router.sheet = .odometer
        case "log": router.sheet = .logService([item("engine_oil"), item("oil_filter")].compactMap { $0?.uuid })
        case "addItems": router.sheet = .addItems
        case "newItem": router.sheet = .newItem(Router.ItemDraft())
        case "entry":
            // The latest entry: split prices and a note.
            let sorted = FetchDescriptor<ServiceEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            if let entry = (try? context.fetch(sorted))?.first { router.sheet = .editEntry(entry) }
        default:
            if value == "item:custom", let i = items.first(where: { $0.catalogKey == nil }) {
                router.sheet = .item(i)
            } else if value.hasPrefix("item:"), let i = item(String(value.dropFirst(5))) {
                router.sheet = .item(i)
            }
        }
    }

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
        let tires = fromCatalog("seasonal_tires")
        tires.kind = .seasonal
        tires.seasonMonths = [4, 10]
        let insurance = fromCatalog("insurance")
        insurance.kind = .expiry
        insurance.validUntil = cal.date(byAdding: .day, value: 38, to: Date())
        // A custom item, shown as typed in every language.
        let washer = item(n("Чистка радіатора", "Чистка радиатора", "Radiator cleaning"), km: 40_000)
        let battery = fromCatalog("battery", months: 60)
        battery.isArchived = true


        let entries: [(Int, Int, [Item])] = [
            (340, 214_000, [oil, oilFilter, lpg, air]),
            (200, 221_000, [cabin]),
            (120, 224_500, [brake]),
            (700, 196_000, [atf, plugs, washer]),
            (40, 227_000, [oil, oilFilter]),
            (900, 190_500, [belt, battery]),
            (330, 215_000, [pads]),
            (150, 223_000, [tires])
        ]
        for (days, km, items) in entries {
            let entry = ServiceEntry(date: daysAgo(days), odometerKm: km, items: items)
            entry.currency = .uah
            switch days {
            case 40:
                entry.setItemCosts([oil.uuid: 2_100, oilFilter.uuid: 450])
                entry.note = "Castrol EDGE 5W-30 LL, 4,7 л"
            case 340: entry.costTotal = 3_900
            case 200: entry.costTotal = 650
            case 120: entry.costTotal = 850
            case 330: entry.costTotal = 2_400
            case 150: entry.costTotal = 600
            case 700: entry.costTotal = 7_800
            default: break
            }
            context.insert(entry)
        }
        context.insert(OdometerReading(date: daysAgo(40), km: 227_000))
        // 20 days ago, so the odometer banner is visible on Home in screenshots.
        context.insert(OdometerReading(date: daysAgo(20), km: 228_100))
        try? context.save()
    }
}
