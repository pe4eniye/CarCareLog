import Foundation

public enum AssistantLanguage: String, Codable, CaseIterable {
    case uk, ru, en
}

public struct QueryPeriod: Equatable {
    public enum Kind: Equatable {
        case thisYear, lastYear, year(Int), thisMonth, lastMonth, last12Months
    }
    public var kind: Kind
    public var start: Date
    /// Exclusive.
    public var end: Date

    public func contains(_ date: Date) -> Bool { date >= start && date < end }
}

public enum AssistantIntent: Equatable {
    case lastDone
    case nextDue
    case partNumber
    case dueAtMileage(Int)
    case historyForPeriod(QueryPeriod)
    /// "How much did I spend (this year)?" — nil period means all time.
    case spending(QueryPeriod?)
    /// "How much was the oil?" — last known price of an item.
    case price
}

public struct ParsedQuery: Equatable {
    public var language: AssistantLanguage
    public var intent: AssistantIntent?
    /// Best matching items, best first. More than one means "ask the user to choose".
    public var itemIDs: [UUID]
}

public enum QueryParser {

    // MARK: Language

    private static let ukWords: Set<String> = [
        "коли", "що", "мені", "цього", "цьому", "року", "році", "рік", "скільки", "потрібно", "треба",
        "востаннє", "міняв", "мінявся", "мінялися", "мінялись", "міняли", "міняти", "поміняти", "замінити",
        "замінив", "наступна", "який", "яка", "які", "пробігу", "пробігом", "тис", "минулого",
        "нагадай", "усе", "якого", "дай", "моє", "мій", "моя", "запалювання", "свічки", "фільтр", "олива",
        "оливу", "мастило", "салону", "останній", "раз", "зараз", "чи", "та", "і", "й"
    ]
    private static let ruWords: Set<String> = [
        "когда", "что", "мне", "этом", "этого", "году", "год", "года", "сколько", "нужно", "надо",
        "последний", "менял", "менялся", "менялись", "менять", "поменять", "заменить", "заменил",
        "следующая", "следующий", "какой", "какая", "какие", "пробеге", "пробегом", "тыс", "прошлом",
        "напомни", "всего", "всё", "все", "мой", "моя", "зажигания", "свечи", "фильтр", "масло", "масла",
        "салона", "раз", "сейчас", "ли", "и", "напиши", "пора", "через", "как"
    ]

    public static func detectLanguage(_ text: String, fallback: AssistantLanguage) -> AssistantLanguage {
        let lower = text.lowercased()
        var cyr = 0, lat = 0, ukScore = 0, ruScore = 0
        for scalar in lower.unicodeScalars {
            switch scalar.value {
            case 0x0400...0x04FF:
                cyr += 1
                if "іїєґ".unicodeScalars.contains(scalar) { ukScore += 2 }
                if "ыэъё".unicodeScalars.contains(scalar) { ruScore += 2 }
            case 0x61...0x7A:
                lat += 1
            default:
                break
            }
        }
        if cyr == 0 { return lat > 0 ? .en : fallback }
        // Ukrainian text of a few words almost always has і/ї/є/ґ.
        if ukScore == 0 && cyr >= 8 { ruScore += 1 }
        for w in TextTools.words(text) {
            if ukWords.contains(w) { ukScore += 1 }
            if ruWords.contains(w) { ruScore += 1 }
        }
        if ukScore > ruScore { return .uk }
        if ruScore > ukScore { return .ru }
        return fallback == .ru ? .ru : .uk
    }

    // MARK: Numbers and periods

    private static let yearWords: Set<String> = ["г", "год", "году", "года", "рік", "році", "року", "р", "year"]
    private static let yearPrepositions: Set<String> = ["в", "у", "за", "in", "during", "of"]
    private static let mileageCues: Set<String> = [
        "на", "до", "at", "by", "upto", "пробег", "пробеге", "пробега", "пробіг", "пробігу", "пробігом",
        "mileage", "odometer", "км", "km"
    ]

    /// Year mentioned explicitly ("в 2025 году", "у 2025", "in 2025").
    static func explicitYear(words: [String]) -> Int? {
        for (i, w) in words.enumerated() {
            guard w.count == 4, let n = Int(w), (1990...2100).contains(n) else { continue }
            let next = i + 1 < words.count ? words[i + 1] : ""
            let prev = i > 0 ? words[i - 1] : ""
            if yearWords.contains(next) || yearPrepositions.contains(prev) { return n }
        }
        return nil
    }

    private static let numberRegex: NSRegularExpression = {
        let pattern = "(?<![\\p{L}\\d])(\\d{1,3}(?:[ \\u00a0.,]\\d{3})+|\\d+)\\s*(тысяч\\p{L}*|тыс\\p{L}*|тис\\p{L}*|thousand\\p{L}*|k|к|км|km)?(?![\\p{L}\\d])"
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

    /// Mileage in km: "250тыс", "250 тис", "250k", "250000", "250 000". Values below 2000 without
    /// a unit mean thousands ("на 250" → 250 000). Years and bare numbers without context are ignored.
    public static func extractMileage(_ text: String) -> Int? {
        let lower = text.lowercased()
        let words = TextTools.words(text)
        let year = explicitYear(words: words)
        let hasCue = words.contains { mileageCues.contains($0) }
        let ns = lower as NSString
        for match in numberRegex.matches(in: lower, range: NSRange(location: 0, length: ns.length)) {
            let digits = ns.substring(with: match.range(at: 1)).filter { $0.isNumber }
            guard let value = Int(digits), value > 0 else { continue }
            var unit = ""
            if match.range(at: 2).location != NSNotFound { unit = ns.substring(with: match.range(at: 2)) }
            if unit.isEmpty && value == year { continue }
            let isThousands = unit.hasPrefix("тыс") || unit.hasPrefix("тис") || unit.hasPrefix("thousand")
                || unit == "k" || unit == "к"
            if isThousands { return value * 1000 }
            if !unit.isEmpty { return value < 2000 ? value * 1000 : value }
            if value >= 2000 || hasCue { return value < 2000 ? value * 1000 : value }
        }
        return nil
    }

    public static func extractPeriod(_ text: String, today: Date, calendar: Calendar) -> QueryPeriod? {
        let norm = " " + TextTools.normalize(text) + " "
        func has(_ phrases: [String]) -> Bool { phrases.contains { norm.contains(" " + $0 + " ") } }

        let year = calendar.component(.year, from: today)
        func yearPeriod(_ y: Int, _ kind: QueryPeriod.Kind) -> QueryPeriod? {
            guard let s = calendar.date(from: DateComponents(year: y, month: 1, day: 1)),
                  let e = calendar.date(from: DateComponents(year: y + 1, month: 1, day: 1)) else { return nil }
            return QueryPeriod(kind: kind, start: s, end: e)
        }
        func monthPeriod(offset: Int, _ kind: QueryPeriod.Kind) -> QueryPeriod? {
            let c = calendar.dateComponents([.year, .month], from: today)
            guard let thisMonth = calendar.date(from: c),
                  let s = calendar.date(byAdding: .month, value: offset, to: thisMonth),
                  let e = calendar.date(byAdding: .month, value: 1, to: s) else { return nil }
            return QueryPeriod(kind: kind, start: s, end: e)
        }

        if has(["прошлом году", "прошлый год", "прошлого года", "минулому році", "минулого року",
                "минулий рік", "торік", "торiк", "last year"]) {
            return yearPeriod(year - 1, .lastYear)
        }
        if has(["этом году", "этот год", "этого года", "текущем году", "цьому році", "цього року",
                "цей рік", "поточному році", "this year"]) {
            return yearPeriod(year, .thisYear)
        }
        if has(["прошлом месяце", "прошлый месяц", "прошлого месяца", "минулому місяці", "минулого місяця",
                "минулий місяць", "last month"]) {
            return monthPeriod(offset: -1, .lastMonth)
        }
        if has(["этом месяце", "этот месяц", "этого месяца", "цьому місяці", "цього місяця", "цей місяць",
                "this month"]) {
            return monthPeriod(offset: 0, .thisMonth)
        }
        if has(["за год", "за последний год", "за рік", "за останній рік", "past year", "last 12 months",
                "за последние 12 месяцев", "за останні 12 місяців"]) {
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today))!
            let start = calendar.date(byAdding: .month, value: -12, to: end)!
            return QueryPeriod(kind: .last12Months, start: start, end: end)
        }
        if let y = explicitYear(words: TextTools.words(text)) {
            return yearPeriod(y, .year(y))
        }
        return nil
    }

    // MARK: Intent keywords (matched on whole normalized words)

    private static let partNumberWords: Set<String> = [
        "номер", "номера", "номери", "номеру", "артикул", "артикула", "артикулу", "oem", "оем",
        "number", "numbers", "аналог", "аналоги", "аналогі", "аналогов", "аналогів", "analog", "analogs",
        "analogue", "analogues", "каталожный", "каталожний", "код"
    ]
    private static let lastDoneWords: Set<String> = [
        "менял", "менялся", "менялась", "менялось", "менялись", "меняли", "меняла", "поменял", "поменяли",
        "поменяла", "заменил", "заменили", "заменила", "заменял", "заменяли", "делал", "делали", "сделал",
        "міняв", "мінявся", "мінялася", "мінялось", "мінялося", "мінялися", "мінялись", "міняли", "міняла",
        "поміняв", "поміняли", "замінив", "замінили", "замінював", "замінювали", "змінював", "змінив",
        "робив", "зробив", "changed", "replaced", "did", "done", "last", "was", "were"
    ]
    private static let lastDonePrefixes = ["последн", "останн", "востанн"]
    private static let nextDueWords: Set<String> = [
        "пора", "нужно", "надо", "следующая", "следующий", "следующую", "следующей", "треба", "потрібно",
        "наступна", "наступний", "наступну", "next", "due", "need", "needs", "should", "через", "менять",
        "поменять", "заменить", "міняти", "поміняти", "замінити", "change", "replace", "скоро", "soon"
    ]
    static let priceWords: Set<String> = [
        "стоил", "стоило", "стоила", "стоили", "стоимость", "цена", "цену", "ціна", "ціну", "коштував", "коштувало",
        "коштувала", "коштували", "вартість", "price", "cost", "costs"
    ]
    static let spendingWords: Set<String> = [
        "потратил", "потратила", "потратили", "потрачено", "расходы", "расход", "расходов", "витратив", "витратила",
        "витратили", "витрачено", "витрати", "витрат", "spent", "spend", "spending", "expenses"
    ]
    private static let historyWords: Set<String> = [
        "что", "що", "what", "which", "все", "всё", "усе", "всього", "всего", "список", "list",
        "история", "историю", "історія", "історію", "history"
    ]

    /// Words removed before item matching.
    static let stopWords: Set<String> = {
        var s: Set<String> = [
            // ru
            "когда", "я", "мы", "раз", "напомни", "дай", "дайте", "напиши", "покажи", "скажи", "что", "на", "в",
            "во", "этом", "году", "с", "по", "и", "а", "мне", "мой", "моя", "мое", "мои", "у", "до", "км",
            "пробег", "пробеге", "тыс", "тысяч", "сколько", "замена", "замены", "замену", "какой", "какая",
            "какие", "ли", "же", "был", "была", "было", "были", "уже", "ещё", "еще", "для", "это", "всего",
            "все", "всё", "список", "машине", "машины", "авто", "мою", "пожалуйста", "нужно",
            // uk
            "коли", "ми", "нагадай", "що", "цього", "року", "році", "рік", "мені", "мій", "моє", "мої", "скільки",
            "заміна", "заміни", "заміну", "який", "яка", "які", "чи", "вже", "ще", "для", "це", "усе", "всього",
            "пробіг", "пробігу", "тис", "будь", "ласка", "та", "й", "машині", "і", "потрібно",
            // en
            "when", "i", "did", "last", "time", "is", "the", "a", "an", "my", "what", "at", "in", "this", "year",
            "give", "me", "how", "of", "for", "to", "do", "does", "was", "were", "it", "please", "show", "tell",
            "list", "everything", "all", "km", "car", "by", "be", "will", "on", "should", "need", "needs",
            "next", "due", "change", "changed", "replace", "replaced", "replacement", "number", "part", "oem",
            "until", "many", "much", "long", "soon", "which", "and"
        ]
        s.formUnion(partNumberWords)
        s.formUnion(priceWords)
        s.formUnion(spendingWords)
        s.formUnion(lastDoneWords)
        s.formUnion(nextDueWords)
        return s
    }()

    static func hasLastDoneMarker(_ words: [String]) -> Bool {
        words.contains { w in lastDoneWords.contains(w) || lastDonePrefixes.contains { w.hasPrefix($0) } }
    }

    // MARK: Parse

    public static func parse(_ text: String, items: [ItemInfo], today: Date, calendar: Calendar,
                             fallbackLanguage: AssistantLanguage) -> ParsedQuery {
        let language = detectLanguage(text, fallback: fallbackLanguage)
        let words = TextTools.words(text)
        // Best matches among all items; on a tie between active and archived items, active ones win.
        var itemIDs = ItemMatcher.match(text, items: items)
        let archived = Set(items.filter(\.isArchived).map(\.id))
        if itemIDs.contains(where: { !archived.contains($0) }) { itemIDs.removeAll { archived.contains($0) } }
        let period = extractPeriod(text, today: today, calendar: calendar)
        let mileage = extractMileage(text)

        let intent: AssistantIntent?
        let lastDone = hasLastDoneMarker(words)
        let asksPrice = words.contains { priceWords.contains($0) }
        let asksSpending = words.contains { spendingWords.contains($0) }
        if words.contains(where: { partNumberWords.contains($0) }) {
            intent = .partNumber
        } else if asksPrice && !itemIDs.isEmpty {
            intent = .price
        } else if asksSpending || asksPrice {
            intent = .spending(period)
        } else if let p = period,
                  itemIDs.isEmpty || words.contains(where: { historyWords.contains($0) }) {
            intent = .historyForPeriod(p)
        } else if let km = mileage {
            intent = .dueAtMileage(km)
        } else if lastDone && itemIDs.isEmpty && words.contains(where: { historyWords.contains($0) }) {
            // "Що я міняв?" without a period: show the last 12 months.
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today))!
            let start = calendar.date(byAdding: .month, value: -12, to: end)!
            intent = .historyForPeriod(QueryPeriod(kind: .last12Months, start: start, end: end))
        } else if lastDone {
            intent = .lastDone
        } else if words.contains(where: { nextDueWords.contains($0) }) || !itemIDs.isEmpty {
            intent = .nextDue
        } else {
            intent = nil
        }
        return ParsedQuery(language: language, intent: intent, itemIDs: itemIDs)
    }
}

/// Finds the user's items mentioned in a question.
public enum ItemMatcher {
    struct Phrase {
        var tokens: [TextTools.Token]
    }

    /// Tokens without stop words and numbers. For item names (`fallbackToAll`), a name made only of
    /// stop words keeps its words so it can still be found.
    static func contentTokens(_ text: String, fallbackToAll: Bool = false) -> [TextTools.Token] {
        let all = TextTools.tokens(text).filter { !$0.word.allSatisfy(\.isNumber) }
        let content = all.filter { !QueryParser.stopWords.contains($0.word) }
        return content.isEmpty && fallbackToAll ? all : content
    }

    /// True when every token of `needle` matches some token of `haystack`.
    static func allMatch(_ needle: [TextTools.Token], in haystack: [TextTools.Token]) -> Bool {
        !needle.isEmpty && needle.allSatisfy { n in haystack.contains { TextTools.matches(n, $0) } }
    }

    /// Item's own phrases (name + aliases) plus phrases of synonym groups the item belongs to.
    static func phrases(for item: ItemInfo) -> [Phrase] {
        let catalogPhrases = item.catalogItem.map { $0.allNames + $0.synonyms } ?? []
        let own = ([item.name] + item.aliases + catalogPhrases)
            .map { contentTokens($0, fallbackToAll: true) }
            .filter { !$0.isEmpty }
        var result = own.map { Phrase(tokens: $0) }
        for group in Synonyms.tokenizedGroups {
            let belongs = own.contains { ownTokens in
                group.contains { groupTokens in
                    let sameWords = allMatch(groupTokens, in: ownTokens) && allMatch(ownTokens, in: groupTokens)
                    let containsMultiWord = groupTokens.count >= 2 && allMatch(groupTokens, in: ownTokens)
                    return sameWords || containsMultiWord
                }
            }
            if belongs {
                result.append(contentsOf: group.map { Phrase(tokens: $0) })
            }
        }
        return result
    }

    /// Returns the best matching item ids. Ranking: more matched words first, then full phrase matches.
    public static func match(_ text: String, items: [ItemInfo]) -> [UUID] {
        matchWithQuality(text, items: items).ids
    }

    /// Best matches and whether at least one whole phrase (name, alias or synonym) matched.
    public static func matchWithQuality(_ text: String, items: [ItemInfo]) -> (ids: [UUID], full: Bool) {
        let query = contentTokens(text)
        guard !query.isEmpty else { return ([], false) }

        struct Score: Comparable {
            var matched: Int
            var full: Bool
            static func < (a: Score, b: Score) -> Bool {
                if a.matched != b.matched { return a.matched < b.matched }
                return !a.full && b.full
            }
        }

        var scored: [(UUID, Score)] = []
        for item in items {
            var best: Score?
            for phrase in phrases(for: item) {
                let matched = phrase.tokens.filter { t in query.contains { TextTools.matches(t, $0) } }.count
                guard matched > 0 else { continue }
                let s = Score(matched: matched, full: matched == phrase.tokens.count)
                if best == nil || best! < s { best = s }
            }
            if let b = best { scored.append((item.id, b)) }
        }
        guard let top = scored.map(\.1).max() else { return ([], false) }
        return (scored.filter { $0.1 == top }.map(\.0), top.full)
    }
}
