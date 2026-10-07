import Foundation

/// Deterministic, locale-aware formatting used by assistant replies (and reusable by the app).
public enum AssistantFormat {
    public static let nbsp = "\u{00A0}"

    /// "220 000 км" (uk/ru) or "220,000 km" (en).
    public static func km(_ value: Int, _ lang: AssistantLanguage) -> String {
        let sep = lang == .en ? "," : nbsp
        let unit = lang == .en ? "km" : "км"
        return groupDigits(value, separator: sep) + nbsp + unit
    }

    public static func groupDigits(_ value: Int, separator: String) -> String {
        let negative = value < 0
        let digits = Array(String(abs(value)))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out += separator }
            out.append(ch)
        }
        return negative ? "-" + out : out
    }

    public static func localeIdentifier(_ lang: AssistantLanguage) -> String {
        switch lang {
        case .uk: return "uk_UA"
        case .ru: return "ru_RU"
        case .en: return "en_GB"
        }
    }

    /// "3 листопада 2026", "3 ноября 2026", "3 November 2026".
    public static func date(_ date: Date, _ lang: AssistantLanguage, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: localeIdentifier(lang))
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "d MMMM y"
        return f.string(from: date)
    }

    /// "жовтень 2026", "октябрь 2026", "October 2026".
    public static func monthYear(_ date: Date, _ lang: AssistantLanguage, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: localeIdentifier(lang))
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "LLLL y"
        return f.string(from: date)
    }
}

/// Reply texts in the three assistant languages.
struct AssistantStrings {
    let lang: AssistantLanguage

    func pick(_ uk: String, _ ru: String, _ en: String) -> String {
        switch lang {
        case .uk: return uk
        case .ru: return ru
        case .en: return en
        }
    }

    var notUnderstood: String {
        pick("Не зрозумів запитання. Спробуйте, наприклад:",
             "Не понял вопрос. Попробуйте, например:",
             "Sorry, I didn't understand. Try, for example:")
    }
    var itemNotFound: String {
        pick("Не знайшов такої позиції у вашому списку запчастин. Спробуйте, наприклад:",
             "Не нашёл такой позиции в вашем списке запчастей. Попробуйте, например:",
             "I couldn't find that item in your parts list. Try, for example:")
    }
    var chooseItem: String {
        pick("Знайшов кілька позицій — оберіть:", "Нашёл несколько позиций — выберите:",
             "Several items match — pick one:")
    }
    func noRecords(_ name: String) -> String {
        pick("\(name): записів ще немає.", "\(name): записей пока нет.", "\(name): no records yet.")
    }
    func noForecast(_ name: String) -> String {
        pick("\(name): записів ще немає, прогноз неможливий.", "\(name): записей пока нет, прогноз невозможен.",
             "\(name): no records yet, so no forecast.")
    }
    func noInterval(_ name: String) -> String {
        pick("\(name): інтервал заміни не задано.", "\(name): интервал замены не задан.",
             "\(name): no replacement interval set.")
    }
    func archived(_ name: String) -> String {
        pick("\(name): позиція в архіві, прогноз не ведеться.", "\(name): позиция в архиве, прогноз не ведётся.",
             "\(name): this item is archived, no forecast.")
    }
    var byTime: String { pick("за часом", "по времени", "by time") }
    var byMileage: String { pick("за пробігом", "по пробегу", "by mileage") }
    func overdue(_ details: String) -> String {
        pick("прострочено (\(details))", "просрочено (\(details))", "overdue (\(details))")
    }
    func atKm(_ km: String) -> String { pick("при \(km)", "на \(km)", "at \(km)") }
    var analogsLabel: String { pick("Аналоги", "Аналоги", "Analogs") }
    func noPartNumber(_ name: String) -> String {
        pick("\(name): номер не вказано.", "\(name): номер не указан.", "\(name): no part number saved.")
    }
    func dueByHeader(_ km: String) -> String {
        pick("До \(km) потрібно замінити:", "До \(km) нужно заменить:", "Due by \(km):")
    }
    func nothingDueBy(_ km: String) -> String {
        pick("До \(km) нічого не заплановано.", "До \(km) ничего не запланировано.", "Nothing is due by \(km).")
    }
    func notCounted(_ names: String) -> String {
        pick("Без записів, не враховано: \(names)", "Без записей, не учтено: \(names)",
             "No records, not included: \(names)")
    }
    var noEntriesInPeriod: String {
        pick("За цей період записів немає.", "За этот период записей нет.", "No entries for this period.")
    }
    func yearLabel(_ year: Int) -> String {
        pick("\(year) рік", "\(year) год", "\(year)")
    }
    var last12Months: String {
        pick("Останні 12 місяців", "Последние 12 месяцев", "Last 12 months")
    }

    var examples: [String] {
        switch lang {
        case .uk:
            return ["Коли я востаннє міняв моторне масло?", "Коли міняти салонний фільтр?", "Номер масла АКП",
                    "Що замінити на 250 тис?", "Що я міняв цього року?"]
        case .ru:
            return ["Когда я последний раз менял моторное масло?", "Когда менять салонный фильтр?",
                    "Номер масла АКП", "Что заменить на 250 тыс?", "Что я менял в этом году?"]
        case .en:
            return ["When did I last change the engine oil?", "When is the cabin filter due?",
                    "ATF part number", "What is due at 250k?", "What did I change this year?"]
        }
    }
}
