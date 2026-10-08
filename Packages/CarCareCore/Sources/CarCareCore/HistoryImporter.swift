import Foundation

/// One line of pasted text turned into a service entry draft.
public struct ImportedRow: Equatable, Identifiable {
    public enum Item: Hashable {
        case existing(UUID)
        case catalog(String)
        case custom(String)
    }

    public var id: UUID
    public var line: String
    public var date: Date?
    public var odometerKm: Int?
    public var items: [Item]
    /// Something was guessed (year only, ambiguous item, short number…): the preview highlights the row.
    public var needsReview: Bool

    public var isUsable: Bool { date != nil && odometerKm != nil && !items.isEmpty }
}

/// Parses free-form history from notes, one entry per line, e.g.
/// "12.03.2024 185000 масло, фильтр салона", "05.2023 170 тыс — колодки перед", "окт 2022 158к ГРМ+помпа".
/// Matching uses the user's items first, then the built-in catalog (names, synonyms, typos, three languages).
public enum HistoryImporter {
    public static func parse(_ text: String, items: [ItemInfo], today: Date, calendar: Calendar) -> [ImportedRow] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.rangeOfCharacter(from: .letters) != nil || $0.rangeOfCharacter(from: .decimalDigits) != nil }
            .map { parseLine($0, items: items, today: today, calendar: calendar) }
    }

    static func parseLine(_ line: String, items: [ItemInfo], today: Date, calendar: Calendar) -> ImportedRow {
        var rest = " " + line.lowercased() + " "
        var review = false

        // 1. Date
        var date: Date?
        if let found = findDate(in: rest, calendar: calendar) {
            let (d, approx, range) = found
            date = d
            review = review || approx
            rest.replaceSubrange(range, with: " ")
        }
        if let d = date, calendar.startOfDay(for: d) > calendar.startOfDay(for: today) {
            date = nil
            review = true
        }

        // 2. Odometer
        var km: Int?
        if let found = findKm(in: rest) {
            let (value, approx, range) = found
            km = value
            review = review || approx
            rest.replaceSubrange(range, with: " ")
        }

        // 3. Items
        var found: [ImportedRow.Item] = []
        for chunk in splitItems(rest) {
            let (item, sure) = matchItem(chunk, items: items)
            if !found.contains(item) { found.append(item) }
            if !sure { review = true }
        }
        if date == nil || km == nil || found.isEmpty { review = true }
        return ImportedRow(id: UUID(), line: line, date: date, odometerKm: km, items: found, needsReview: review)
    }

    // MARK: Dates

    private static let monthStems: [(String, Int)] = [
        ("январ", 1), ("феврал", 2), ("март", 3), ("апрел", 4), ("май", 5), ("мая", 5), ("июн", 6), ("июл", 7),
        ("август", 8), ("сентябр", 9), ("октябр", 10), ("ноябр", 11), ("декабр", 12),
        ("січ", 1), ("лют", 2), ("берез", 3), ("квіт", 4), ("трав", 5), ("черв", 6), ("лип", 7), ("серп", 8),
        ("верес", 9), ("жовт", 10), ("листоп", 11), ("груд", 12),
        ("янв", 1), ("фев", 2), ("мар", 3), ("апр", 4), ("сен", 9), ("окт", 10), ("ноя", 11), ("дек", 12),
        ("jan", 1), ("feb", 2), ("mar", 3), ("apr", 4), ("may", 5), ("jun", 6), ("jul", 7), ("aug", 8),
        ("sep", 9), ("oct", 10), ("nov", 11), ("dec", 12)
    ]

    private static func regex(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
    private static let fullDate = regex("(?<!\\d)(\\d{1,2})[./-](\\d{1,2})[./-](\\d{4}|\\d{2})(?!\\d)")
    private static let monthYear = regex("(?<!\\d)(\\d{1,2})[./-](\\d{4})(?!\\d)")
    private static let namedMonth = regex("([a-zа-яёіїєґ]+)\\.?\\s+(\\d{4})(?!\\d)")
    private static let yearOnly = regex("(?<!\\d)(19\\d{2}|20\\d{2})(?!\\d)\\s*(г\\.?|год[а-я]*|р\\.?|рік|року|year)?")

    static func findDate(in s: String, calendar: Calendar) -> (Date, Bool, Range<String.Index>)? {
        let ns = s as NSString
        let whole = NSRange(location: 0, length: ns.length)
        func int(_ m: NSTextCheckingResult, _ i: Int) -> Int { Int(ns.substring(with: m.range(at: i))) ?? 0 }
        func make(_ y: Int, _ m: Int, _ d: Int) -> Date? {
            guard (1...12).contains(m), (1...31).contains(d), (1980...2100).contains(y) else { return nil }
            return calendar.date(from: DateComponents(year: y, month: m, day: d))
        }
        if let m = fullDate.firstMatch(in: s, range: whole) {
            var y = int(m, 3)
            if y < 100 { y += 2000 }
            if let d = make(y, int(m, 2), int(m, 1)), let r = Range(m.range, in: s) { return (d, false, r) }
        }
        if let m = monthYear.firstMatch(in: s, range: whole),
           let d = make(int(m, 2), int(m, 1), 1), let r = Range(m.range, in: s) {
            return (d, false, r)
        }
        for m in namedMonth.matches(in: s, range: whole) {
            let word = ns.substring(with: m.range(at: 1))
            if let month = monthStems.first(where: { word.hasPrefix($0.0) })?.1,
               let d = make(int(m, 2), month, 1), let r = Range(m.range, in: s) {
                return (d, false, r)
            }
        }
        if let m = yearOnly.firstMatch(in: s, range: whole),
           let d = make(int(m, 1), 1, 1), let r = Range(m.range, in: s) {
            return (d, true, r) // year only: approximate
        }
        return nil
    }

    // MARK: Odometer

    private static let number = regex(
        "(?<![\\p{L}\\d])(\\d{1,3}(?:[ \\u00a0.,]\\d{3})+|\\d+)\\s*(тысяч\\p{L}*|тыс\\p{L}*|тис\\p{L}*|thousand|k|к|т|km|км)?(?![\\p{L}\\d])")

    static func findKm(in s: String) -> (Int, Bool, Range<String.Index>)? {
        let ns = s as NSString
        for m in number.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let digits = ns.substring(with: m.range(at: 1)).filter(\.isNumber)
            guard let value = Int(digits), value > 0, let r = Range(m.range, in: s) else { continue }
            let unit = m.range(at: 2).location == NSNotFound ? "" : ns.substring(with: m.range(at: 2))
            let thousands = ["k", "к", "т", "thousand"].contains(unit) || unit.hasPrefix("тыс") || unit.hasPrefix("тис")
            if thousands { return (value * 1000, false, r) }
            if value >= 1000 { return (value, false, r) }
            if value >= 10 { return (value * 1000, true, r) } // "170 — колодки": probably thousands
        }
        return nil
    }

    // MARK: Items

    private static let fillerWords: Set<String> = [
        "замена", "заміна", "замінив", "заменил", "менял", "міняв", "поменял", "поміняв", "change", "changed",
        "replaced", "км", "km", "пробег", "пробіг", "на", "в", "у"
    ]

    static func splitItems(_ s: String) -> [String] {
        var t = s
        for sep in [" и ", " та ", " і ", " and ", " & ", "+", ";", "/", "—", "–", " - ", ":"] {
            t = t.replacingOccurrences(of: sep, with: ",")
        }
        return t.components(separatedBy: ",")
            .map { chunk in
                chunk.split(separator: " ").map(String.init)
                    .filter { !fillerWords.contains($0.trimmingCharacters(in: .punctuationCharacters)) }
                    .joined(separator: " ")
                    .trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))
            }
            .filter { $0.count >= 2 }
    }

    /// The user's items first, then the catalog. `sure` is false for ambiguous or unknown chunks.
    static func matchItem(_ chunk: String, items: [ItemInfo]) -> (ImportedRow.Item, Bool) {
        // The user's items only on a whole-phrase match ("колодки перед" must not stick to an unrelated item).
        let own = ItemMatcher.matchWithQuality(chunk, items: items)
        if own.full, let first = own.ids.first { return (.existing(first), own.ids.count == 1) }

        var byID: [UUID: CatalogItem] = [:]
        let pseudo = Catalog.items.map { c -> ItemInfo in
            let info = ItemInfo(name: c.ru, catalogKey: c.key)
            byID[info.id] = c
            return info
        }
        // A catalog item only when a whole name matched or every word of the chunk did:
        // one shared word out of several ("радіатор" vs "Масло варіатора") is not enough.
        let fromCatalog = ItemMatcher.matchDetailed(chunk, items: pseudo)
        if fromCatalog.full || fromCatalog.covered, let first = fromCatalog.ids.first, let c = byID[first] {
            if let mine = items.first(where: { $0.catalogKey == c.key }) { return (.existing(mine.id), true) }
            return (.catalog(c.key), fromCatalog.ids.count == 1)
        }
        // Only a partial match with the user's items: suggest it, but flag the row.
        if let first = own.ids.first { return (.existing(first), false) }
        let name = chunk.prefix(1).uppercased() + chunk.dropFirst()
        return (.custom(String(name.prefix(Limits.itemName))), false)
    }
}
