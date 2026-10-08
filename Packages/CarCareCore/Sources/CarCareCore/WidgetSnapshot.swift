import Foundation

/// Data the widget shows. The app writes it as JSON into the App Group container on every data change.
/// Texts are already localized by the app, so the widget needs no language logic.
public struct WidgetSnapshot: Codable, Equatable {
    public var generatedAt: Date
    /// Nearest upcoming due day, if any.
    public var dueDay: Date?
    /// "20 листопада"
    public var dueDayText: String
    /// "Масло + фільтр"
    public var itemsText: String
    /// "Прострочено: 2" or empty.
    public var overdueText: String
    /// Shown when there is nothing to forecast.
    public var emptyText: String
    /// Items due on dueDay: tapping the widget opens "Log service" with them selected.
    public var itemIDs: [UUID] = []

    public init(generatedAt: Date, dueDay: Date?, dueDayText: String, itemsText: String, overdueText: String,
                emptyText: String, itemIDs: [UUID] = []) {
        self.generatedAt = generatedAt
        self.dueDay = dueDay
        self.dueDayText = dueDayText
        self.itemsText = itemsText
        self.overdueText = overdueText
        self.emptyText = emptyText
        self.itemIDs = itemIDs
    }

    public static let fileName = "widget-snapshot.json"
}

public enum WidgetSummary {
    public struct Result: Equatable {
        public var dueDay: Date?
        public var itemNames: [String]
        public var overdueNames: [String]
        public var itemIDs: [UUID] = []
    }

    /// Nearest month card (first day of the month) with all items due that month (in list order), plus overdue items.
    public static func make(snapshot: DataSnapshot, today: Date, calendar: Calendar) -> Result {
        let statuses = ForecastEngine.statuses(for: snapshot, today: today, calendar: calendar)
        let groups = ForecastGroups.make(from: statuses, calendar: calendar)
        let order = Dictionary(snapshot.items.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let names = Dictionary(snapshot.items.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        func sortedNames(_ forecasts: [ItemForecast]) -> [String] {
            forecasts.sorted { (order[$0.itemID] ?? 0) < (order[$1.itemID] ?? 0) }.compactMap { names[$0.itemID] }
        }
        let next = groups.upcoming.first
        let ids = (next?.forecasts ?? []).sorted { (order[$0.itemID] ?? 0) < (order[$1.itemID] ?? 0) }.map { $0.itemID }
        return Result(dueDay: next?.month, itemNames: next.map { sortedNames($0.forecasts) } ?? [],
                      overdueNames: sortedNames(groups.overdue), itemIDs: ids)
    }
}
