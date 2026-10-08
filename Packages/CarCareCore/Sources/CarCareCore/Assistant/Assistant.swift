import Foundation

public struct ReplyLine: Equatable {
    public var text: String
    /// Values the UI offers to copy (part numbers).
    public var copyValues: [String]

    public init(_ text: String, copyValues: [String] = []) {
        self.text = text
        self.copyValues = copyValues
    }
}

public struct ItemChoice: Equatable, Identifiable {
    public var id: UUID
    public var name: String
}

public struct AssistantReply: Equatable {
    public enum Kind: Equatable {
        case answer
        case chooseItem
        case itemNotFound
        case notUnderstood
    }

    public var kind: Kind
    public var language: AssistantLanguage
    public var intent: AssistantIntent?
    public var lines: [ReplyLine]
    public var choices: [ItemChoice]
    public var examples: [String]

    public var text: String { lines.map(\.text).joined(separator: "\n") }
}

public struct AssistantContext {
    public var snapshot: DataSnapshot
    public var today: Date
    public var calendar: Calendar
    /// Used when the language of the question can't be detected (e.g. only digits).
    public var fallbackLanguage: AssistantLanguage
    /// Currency for spending answers (the app setting).
    public var currency: Currency

    public init(snapshot: DataSnapshot, today: Date, calendar: Calendar, fallbackLanguage: AssistantLanguage,
                currency: Currency = .uah) {
        self.currency = currency
        self.snapshot = snapshot
        self.today = today
        self.calendar = calendar
        self.fallbackLanguage = fallbackLanguage
    }
}

/// Offline, rule-based assistant. Never invents data: every answer comes from the snapshot.
public enum Assistant {
    /// Example questions for the chips under the input field.
    public static func examples(_ language: AssistantLanguage) -> [String] {
        AssistantStrings(lang: language).examples
    }

    /// - Parameter chosenItemID: set when the user tapped one of the offered choices.
    public static func answer(_ question: String, context: AssistantContext,
                              chosenItemID: UUID? = nil) -> AssistantReply {
        let snap = context.snapshot
        var parsed = QueryParser.parse(question, items: snap.items, today: context.today,
                                       calendar: context.calendar, fallbackLanguage: context.fallbackLanguage)
        if let chosen = chosenItemID { parsed.itemIDs = [chosen] }
        let s = AssistantStrings(lang: parsed.language)

        func reply(_ kind: AssistantReply.Kind, _ lines: [ReplyLine], choices: [ItemChoice] = [],
                   examples: [String] = []) -> AssistantReply {
            AssistantReply(kind: kind, language: parsed.language, intent: parsed.intent, lines: lines,
                           choices: choices, examples: examples)
        }

        guard let intent = parsed.intent else {
            return reply(.notUnderstood, [ReplyLine(s.notUnderstood)], examples: s.examples)
        }

        switch intent {
        case .dueAtMileage(let km):
            return reply(.answer, dueAtMileage(km, context: context, strings: s))
        case .historyForPeriod(let period):
            return reply(.answer, history(period, context: context, strings: s))
        case .spending(let period):
            return reply(.answer, spending(period, context: context, strings: s))
        case .lastDone, .nextDue, .partNumber, .price:
            let items = parsed.itemIDs.compactMap { snap.item(id: $0) }
            if items.isEmpty {
                return reply(.itemNotFound, [ReplyLine(s.itemNotFound)], examples: s.examples)
            }
            if items.count > 1 {
                return reply(.chooseItem, [ReplyLine(s.chooseItem)],
                             choices: items.map { ItemChoice(id: $0.id, name: $0.name) })
            }
            let item = items[0]
            switch intent {
            case .lastDone: return reply(.answer, lastDone(item, context: context, strings: s))
            case .nextDue: return reply(.answer, nextDue(item, context: context, strings: s))
            case .price: return reply(.answer, price(item, context: context, strings: s))
            default: return reply(.answer, partNumber(item, strings: s))
            }
        }
    }

    // MARK: Answers

    static func lastDone(_ item: ItemInfo, context: AssistantContext, strings s: AssistantStrings) -> [ReplyLine] {
        guard let last = ForecastEngine.lastEntry(for: item.id, entries: context.snapshot.entries) else {
            return [ReplyLine(s.noRecords(item.name))]
        }
        let km = AssistantFormat.km(last.odometerKm, s.lang)
        let date = AssistantFormat.date(last.date, s.lang, calendar: context.calendar)
        return [ReplyLine("\(item.name): \(km) (\(date))")]
    }

    static func nextDue(_ item: ItemInfo, context: AssistantContext, strings s: AssistantStrings) -> [ReplyLine] {
        let snap = context.snapshot
        if item.isArchived { return [ReplyLine(s.archived(item.name))] }
        let status = ForecastEngine.status(for: item, entries: snap.entries, currentOdometerKm: snap.currentOdometerKm,
                                           avgKmPerMonth: MileageEstimator.estimate(snapshot: snap, today: context.today,
                                                                                    calendar: context.calendar).value,
                                           today: context.today,
                                           calendar: context.calendar)
        switch status {
        case .noInterval:
            return [ReplyLine(s.noInterval(item.name))]
        case .noHistory:
            return [ReplyLine(s.noForecast(item.name))]
        case .forecast(let f):
            return [ReplyLine("\(item.name): \(describe(f, context: context, strings: s))")]
        }
    }

    /// "20 листопада 2026 (≈ 245 000 км) — за пробігом", "прострочено (…)", "при 245 000 км".
    static func describe(_ f: ItemForecast, context: AssistantContext, strings s: AssistantStrings) -> String {
        let cal = context.calendar
        if f.isOverdue {
            var parts: [String] = []
            let limits = f.overdueLimits
            if let d = limits.date { parts.append(AssistantFormat.date(d, s.lang, calendar: cal)) }
            if let km = limits.km { parts.append(AssistantFormat.km(km, s.lang)) }
            return s.overdue(parts.joined(separator: ", "))
        }
        guard let d = f.dueDate else {
            return s.atKm(AssistantFormat.km(f.dueKm ?? f.predictedOdometerKm, s.lang))
        }
        let date = AssistantFormat.date(d, s.lang, calendar: cal)
        let km = AssistantFormat.km(f.predictedOdometerKm, s.lang)
        if f.reason == .mileage {
            return "\(date) (\(km)) — \(s.byMileage)"
        }
        return "\(date) (≈\(AssistantFormat.nbsp)\(km)) — \(s.byTime)"
    }

    static func partNumber(_ item: ItemInfo, strings s: AssistantStrings) -> [ReplyLine] {
        let oem = item.oemNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let analogs = PartNumbers.cleanList(item.analogNumbers)
        if oem.isEmpty && analogs.isEmpty { return [ReplyLine(s.noPartNumber(item.name))] }
        var lines = [ReplyLine(item.name)]
        if !oem.isEmpty { lines.append(ReplyLine("OEM: \(oem)", copyValues: [oem])) }
        if !analogs.isEmpty {
            lines.append(ReplyLine("\(s.analogsLabel): \(analogs.joined(separator: ", "))", copyValues: analogs))
        }
        return lines
    }

    static func dueAtMileage(_ limit: Int, context: AssistantContext, strings s: AssistantStrings) -> [ReplyLine] {
        let snap = context.snapshot
        let avg = MileageEstimator.estimate(snapshot: snap, today: context.today, calendar: context.calendar).value
        let statuses = ForecastEngine.statuses(for: snap, today: context.today, calendar: context.calendar)
        var hits: [(ItemInfo, ItemForecast, Int)] = []
        var noHistory: [String] = []
        for item in snap.activeItems {
            switch statuses[item.id] {
            case .forecast(let f)?:
                var kmAtDue: Int?
                if f.reason == .mileage, let km = f.dueKm { kmAtDue = km } else if avg > 0 { kmAtDue = f.predictedOdometerKm }
                let byKm = (f.dueKm ?? Int.max) <= limit
                let byProjection = (kmAtDue ?? Int.max) <= limit
                if f.isOverdue || byKm || byProjection {
                    hits.append((item, f, min(kmAtDue ?? Int.max, f.dueKm ?? Int.max)))
                }
            case .noHistory?:
                noHistory.append(item.name)
            default:
                break
            }
        }
        let limitText = AssistantFormat.km(limit, s.lang)
        var lines: [ReplyLine] = []
        if hits.isEmpty {
            lines.append(ReplyLine(s.nothingDueBy(limitText)))
        } else {
            lines.append(ReplyLine(s.dueByHeader(limitText)))
            for (item, f, _) in hits.sorted(by: { $0.2 < $1.2 }) {
                lines.append(ReplyLine("• \(item.name) — \(describe(f, context: context, strings: s))"))
            }
        }
        if !noHistory.isEmpty {
            lines.append(ReplyLine(s.notCounted(noHistory.joined(separator: ", "))))
        }
        return lines
    }

    static func history(_ period: QueryPeriod, context: AssistantContext, strings s: AssistantStrings) -> [ReplyLine] {
        let snap = context.snapshot
        let cal = context.calendar
        let header: String
        switch period.kind {
        case .thisYear, .lastYear:
            header = s.yearLabel(cal.component(.year, from: period.start))
        case .year(let y):
            header = s.yearLabel(y)
        case .thisMonth, .lastMonth:
            header = AssistantFormat.monthYear(period.start, s.lang, calendar: cal)
        case .last12Months:
            header = s.last12Months
        }
        let entries = snap.entries
            .filter { period.contains($0.date) }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.odometerKm > $1.odometerKm }
        guard !entries.isEmpty else {
            return [ReplyLine("\(header):"), ReplyLine(s.noEntriesInPeriod)]
        }
        var lines = [ReplyLine("\(header):")]
        for e in entries {
            let names = e.displayNames(items: snap.items).joined(separator: ", ")
            let date = AssistantFormat.date(e.date, s.lang, calendar: cal)
            lines.append(ReplyLine("\(date) · \(AssistantFormat.km(e.odometerKm, s.lang)) — \(names)"))
        }
        return lines
    }
}

extension Assistant {
    static func spending(_ period: QueryPeriod?, context: AssistantContext, strings s: AssistantStrings) -> [ReplyLine] {
        let snap = context.snapshot
        let interval = period.map { DateInterval(start: $0.start, end: $0.end) }
        let header: String
        if let period {
            switch period.kind {
            case .thisYear, .lastYear:
                header = s.yearLabel(context.calendar.component(.year, from: period.start))
            case .year(let y):
                header = s.yearLabel(y)
            case .thisMonth, .lastMonth:
                header = AssistantFormat.monthYear(period.start, s.lang, calendar: context.calendar)
            case .last12Months:
                header = s.last12Months
            }
        } else {
            header = s.allTime
        }
        let totals = Expenses.totalsByCurrency(snap, in: interval)
        guard !totals.isEmpty else { return [ReplyLine("\(header):"), ReplyLine(s.noSpending)] }
        // The app currency first, others after it.
        let ordered = totals.sorted { a, b in (a.0 == context.currency ? 0 : 1) < (b.0 == context.currency ? 0 : 1) }
        let amounts = ordered.map { AssistantFormat.money($0.1, $0.0, s.lang) }.joined(separator: " + ")
        let count = Expenses.lines(snap, in: interval).count
        return [ReplyLine("\(header):"), ReplyLine(s.spent(amounts, count))]
    }

    static func price(_ item: ItemInfo, context: AssistantContext, strings s: AssistantStrings) -> [ReplyLine] {
        guard let p = Expenses.lastPrice(of: item.id, in: context.snapshot) else {
            return [ReplyLine(s.noPrice(item.name))]
        }
        let date = AssistantFormat.date(p.date, s.lang, calendar: context.calendar)
        return [ReplyLine("\(item.name): \(AssistantFormat.money(p.amount, p.currency, s.lang)) (\(date))")]
    }
}
