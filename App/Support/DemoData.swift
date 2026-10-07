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

        let oil = item(n("Моторне масло", "Моторное масло", "Engine oil"), km: 10_000, months: 12,
                       oem: "G 052 195 M4", analogs: ["Castrol EDGE 5W-30 LL"])
        let oilFilter = item(n("Масляний фільтр", "Масляный фильтр", "Oil filter"), km: 10_000, months: 12,
                             oem: "03C 115 562", analogs: ["MANN W 719/45", "BOSCH F 026 407 209"])
        let cabin = item(n("Фільтр салону", "Фильтр салона", "Cabin filter"), km: 15_000, months: 12,
                         oem: "5Q0 819 653")
        let air = item(n("Повітряний фільтр", "Воздушный фильтр", "Air filter"), km: 30_000, months: 24,
                       oem: "5Q0 129 620 B")
        let atf = item(n("Масло АКП", "Масло АКП", "ATF"), km: 60_000, oem: "G 052 182 A2",
                       analogs: ["Febi 39070"], aliases: ["ATF", "DSG"])
        let plugs = item(n("Свічки запалювання", "Свечи зажигания", "Spark plugs"), km: 60_000,
                         oem: "04E 905 612 C")
        let lpg = item(n("Фільтри ГБО", "Фильтры ГБО", "LPG filters"), km: 10_000)
        let brake = item(n("Гальмівна рідина", "Тормозная жидкость", "Brake fluid"), months: 24)
        let belt = item(n("Ремінь ГРМ", "Ремень ГРМ", "Timing belt"), km: 90_000, months: 60)
        let battery = item(n("Акумулятор", "Аккумулятор", "Battery"), months: 60)
        battery.isArchived = true

        let entries: [(Int, Int, [Item])] = [
            (340, 214_000, [oil, oilFilter, lpg, air]),
            (200, 221_000, [cabin]),
            (120, 224_500, [brake]),
            (700, 196_000, [atf, plugs]),
            (40, 227_000, [oil, oilFilter]),
            (900, 190_500, [belt, battery])
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
