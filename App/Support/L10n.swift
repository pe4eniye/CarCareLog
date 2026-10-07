import Foundation
import CarCareCore

/// In-app language override. All UI and notification texts go through `L10n.t`, which reads the
/// compiled String Catalog from the chosen language's .lproj instead of the system language.
enum L10n {
    static let supported = ["uk", "en"]

    private(set) static var language = "uk"
    private(set) static var bundle: Bundle = loadBundle("uk")

    static func setLanguage(_ code: String) {
        let lang = supported.contains(code) ? code : "uk"
        language = lang
        bundle = loadBundle(lang)
    }

    private static func loadBundle(_ code: String) -> Bundle {
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"), let b = Bundle(path: path) { return b }
        return .main
    }

    static var locale: Locale { Locale(identifier: language == "en" ? "en_GB" : "uk_UA") }

    static var assistantLanguage: AssistantLanguage { language == "en" ? .en : .uk }

    static func t(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), locale: locale, arguments: args)
    }
}

/// Shared date/number formatting in the chosen app language.
enum Fmt {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = L10n.locale
        c.timeZone = .current
        return c
    }

    static func km(_ value: Int) -> String {
        AssistantFormat.km(value, L10n.assistantLanguage)
    }

    /// "20 листопада 2026"
    static func date(_ date: Date) -> String {
        AssistantFormat.date(date, L10n.assistantLanguage, calendar: calendar)
    }

    /// "20 листопада" for dates in the current year, otherwise with the year.
    static func shortDate(_ date: Date) -> String {
        let cal = calendar
        if cal.component(.year, from: date) != cal.component(.year, from: Date()) { return Fmt.date(date) }
        let f = DateFormatter()
        f.locale = L10n.locale
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.dateFormat = "d MMMM"
        return f.string(from: date)
    }

    /// Parses digits from user input ("228 000" → 228000).
    static func parseInt(_ text: String) -> Int? {
        let digits = text.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }
}
