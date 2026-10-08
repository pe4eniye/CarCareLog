import Foundation
import CarCareCore

/// One-line descriptions of a forecast, shared by Home, Schedule and the widgets.
/// Time-based items say "in ~5 mo." (or days), mileage-based ones "in 7 900 km · ≈ 236 000 km".
enum ForecastText {
    static func detail(kind: ItemKind, forecast f: ItemForecast, currentKm: Int?, today: Date) -> String {
        let cal = Fmt.calendar
        let days = f.daysLeft(today: today, calendar: cal) ?? 0
        if f.isOverdue {
            switch kind {
            case .expiry:
                return L10n.f("text.expired", f.dueDate.map(Fmt.date) ?? "")
            case .seasonal:
                return L10n.f("text.seasonMissed", f.dueDate.map(Fmt.monthYear) ?? "")
            case .interval:
                var parts: [String] = []
                let limits = f.overdueLimits
                if let km = limits.km {
                    parts.append(L10n.f("home.overdueKm", Fmt.km(km)))
                    if let cur = currentKm, cur > km { parts.append(L10n.f("home.overBy", Fmt.km(cur - km))) }
                }
                if let d = limits.date { parts.append(L10n.f("home.overdueDate", Fmt.date(d))) }
                return parts.joined(separator: " · ")
            }
        }
        switch kind {
        case .expiry:
            return L10n.f("text.validUntil", f.dueDate.map(Fmt.date) ?? "") + " · " + timeLeft(days)
        case .seasonal:
            return L10n.f("text.season", f.dueDate.map(Fmt.monthYear) ?? "") + " · " + timeLeft(days)
        case .interval:
            if f.dueDate == nil, let km = f.dueKm { return L10n.f("home.atKm", Fmt.km(km)) }
            if f.reason == .mileage {
                var text = ""
                if let left = f.kmLeft(currentOdometerKm: currentKm), left > 0 { text = L10n.f("home.inKm", Fmt.km(left)) + " · " }
                return text + "≈ " + Fmt.km(f.predictedOdometerKm)
            }
            return timeLeft(days)
        }
    }

    /// "today", "in 12 d", "in ~5 mo."
    static func timeLeft(_ days: Int) -> String {
        if days <= 0 { return L10n.t("text.today") }
        if days < 45 { return L10n.f("text.inDays", days) }
        return L10n.f("text.inMonths", Int((Double(days) / ForecastEngine.daysPerMonth).rounded()))
    }

    /// Short value for the round lock screen widget: "8,9k km" / "38 d" / "5 mo".
    static func short(kind: ItemKind, forecast f: ItemForecast, currentKm: Int?, today: Date) -> String {
        if f.isOverdue { return "!" }
        if kind == .interval, f.reason == .mileage, let left = f.kmLeft(currentOdometerKm: currentKm) {
            if left >= 1000 {
                let thousands = (Double(left) / 100).rounded() / 10
                return L10n.f("text.shortThousandKm", String(format: thousands == thousands.rounded() ? "%.0f" : "%.1f", thousands))
            }
            return L10n.f("text.shortKm", left)
        }
        let days = f.daysLeft(today: today, calendar: Fmt.calendar) ?? 0
        if days < 45 { return L10n.f("text.shortDays", days) }
        return L10n.f("text.shortMonths", Int((Double(days) / ForecastEngine.daysPerMonth).rounded()))
    }
}
