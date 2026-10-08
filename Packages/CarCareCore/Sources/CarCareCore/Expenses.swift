import Foundation

/// Spending statistics from service entries. Amounts are never mixed across currencies:
/// every function takes the currency to count, and `currencies` lists which ones exist.
public enum Expenses {
    public struct Line: Equatable, Identifiable {
        public var id: UUID
        public var date: Date
        public var odometerKm: Int
        public var amount: Double
        public var currency: Currency
        public var names: [String]
    }

    /// Entries with a cost, newest first.
    public static func lines(_ snapshot: DataSnapshot, currency: Currency? = nil,
                             in period: DateInterval? = nil) -> [Line] {
        snapshot.entries
            .filter { ($0.costTotal ?? 0) > 0 }
            .filter { currency == nil || $0.currency == currency }
            .filter { period == nil || period!.contains($0.date) }
            .sorted { $0.date > $1.date }
            .map { Line(id: $0.id, date: $0.date, odometerKm: $0.odometerKm, amount: $0.costTotal ?? 0,
                        currency: $0.currency, names: $0.displayNames(items: snapshot.items)) }
    }

    public static func total(_ snapshot: DataSnapshot, currency: Currency, in period: DateInterval? = nil) -> Double {
        lines(snapshot, currency: currency, in: period).reduce(0) { $0 + $1.amount }
    }

    /// Totals in every currency used in the period, biggest first.
    public static func totalsByCurrency(_ snapshot: DataSnapshot, in period: DateInterval? = nil) -> [(Currency, Double)] {
        Currency.allCases
            .map { ($0, total(snapshot, currency: $0, in: period)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
    }

    /// 12 monthly totals for a calendar year.
    public static func byMonth(_ snapshot: DataSnapshot, currency: Currency, year: Int, calendar: Calendar) -> [Double] {
        var result = Array(repeating: 0.0, count: 12)
        for line in lines(snapshot, currency: currency) where calendar.component(.year, from: line.date) == year {
            result[calendar.component(.month, from: line.date) - 1] += line.amount
        }
        return result
    }

    /// Spending by catalog category (nil = custom items, "Other"). An entry's total is split by item prices when
    /// they were entered, otherwise equally between its items.
    public static func byCategory(_ snapshot: DataSnapshot, currency: Currency,
                                  in period: DateInterval? = nil) -> [(CatalogItem.Category?, Double)] {
        var sums: [CatalogItem.Category?: Double] = [:]
        for entry in snapshot.entries where entry.currency == currency {
            guard let total = entry.costTotal, total > 0, !entry.itemIDs.isEmpty else { continue }
            if let period, !period.contains(entry.date) { continue }
            let hasSplit = entry.itemCosts.contains { $0 != nil }
            for (index, _) in entry.itemIDs.enumerated() {
                let key = index < entry.itemCatalogKeys.count ? entry.itemCatalogKeys[index] : ""
                let category = Catalog.item(key.isEmpty ? nil : key)?.category
                let share: Double
                if hasSplit {
                    share = index < entry.itemCosts.count ? (entry.itemCosts[index] ?? 0) : 0
                } else {
                    share = total / Double(entry.itemIDs.count)
                }
                sums[category, default: 0] += share
            }
        }
        return sums.filter { $0.value > 0 }.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    /// The most recent known price of an item (from split prices, or single-item entries).
    public static func lastPrice(of itemID: UUID, in snapshot: DataSnapshot) -> (amount: Double, currency: Currency, date: Date)? {
        snapshot.entries
            .filter { $0.itemIDs.contains(itemID) }
            .sorted { $0.date > $1.date }
            .lazy
            .compactMap { e in e.cost(of: itemID).map { ($0, e.currency, e.date) } }
            .first
    }

    public static func year(_ year: Int, calendar: Calendar) -> DateInterval {
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
        return DateInterval(start: start, end: end)
    }

    public static func month(of date: Date, calendar: Calendar) -> DateInterval {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        return DateInterval(start: start, end: calendar.date(byAdding: .month, value: 1, to: start)!)
    }
}

extension AssistantFormat {
    /// "2 950 ₴", "€1 200,50" style kept simple and deterministic: groups of 3, up to 2 decimals.
    public static func money(_ amount: Double, _ currency: Currency, _ lang: AssistantLanguage) -> String {
        let rounded = (amount * 100).rounded() / 100
        let whole = Int(rounded)
        let cents = Int(((rounded - Double(whole)) * 100).rounded())
        let sep = lang == .en ? "," : nbsp
        let decimal = lang == .en ? "." : ","
        var number = groupDigits(whole, separator: sep)
        if cents != 0 { number += decimal + String(format: "%02d", cents) }
        switch currency {
        case .uah: return number + nbsp + "₴"
        case .usd: return "$" + number
        case .eur: return lang == .en ? "€" + number : number + nbsp + "€"
        }
    }
}
