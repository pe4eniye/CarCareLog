import Foundation

/// Input limits shared by all forms.
public enum Limits {
    public static let carName = 40
    public static let itemName = 60
    public static let alias = 40
    public static let partNumber = 30
    public static let vin = 17
    public static let odometer = 0...2_000_000
    public static let intervalKm = 100...500_000
    public static let intervalMonths = 1...240
    public static let avgKmPerMonth = 1...20_000
}

public enum FieldError: Equatable {
    case required
    case tooLong(max: Int)
    case outOfRange(min: Int, max: Int)
    case dateInFuture
    /// An active item already has this name.
    case duplicate(name: String)
}

public enum ValidationRules {
    public static func text(_ value: String, required: Bool, max: Int) -> FieldError? {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if required && t.isEmpty { return .required }
        if t.count > max { return .tooLong(max: max) }
        return nil
    }

    public static func number(_ value: Int?, required: Bool, range: ClosedRange<Int>) -> FieldError? {
        guard let v = value else { return required ? .required : nil }
        return range.contains(v) ? nil : .outOfRange(min: range.lowerBound, max: range.upperBound)
    }

    public static func pastOrToday(_ date: Date?, now: Date, calendar: Calendar) -> FieldError? {
        guard let d = date else { return .required }
        return calendar.startOfDay(for: d) > calendar.startOfDay(for: now) ? .dateInFuture : nil
    }

    public enum EntryProblem: Equatable {
        case dateInFuture
        case noItems
        case negativeOdometer
    }

    public static func validateEntry(date: Date, odometerKm: Int, itemCount: Int,
                                     now: Date, calendar: Calendar) -> [EntryProblem] {
        var problems: [EntryProblem] = []
        if calendar.startOfDay(for: date) > calendar.startOfDay(for: now) { problems.append(.dateInFuture) }
        if itemCount == 0 { problems.append(.noItems) }
        if odometerKm < 0 { problems.append(.negativeOdometer) }
        return problems
    }

    /// Soft warning only: a VIN is normally 17 characters.
    public static func vinLooksWrong(_ vin: String?) -> Bool {
        guard let v = vin?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return false }
        return v.count != 17
    }
}

/// Item names are unique among items, ignoring case, extra spaces and ё/е.
public enum ItemNameRules {
    public static func key(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    public enum Conflict: Equatable {
        case none
        /// An active item has the same name (in any language for catalog items): saving is not allowed.
        case active(ItemInfo)
        /// Only an archived item has this name: offer "Restore from archive" or "Create new".
        case archived(ItemInfo)
        /// Not used yet, but the built-in catalog has this item: offer to take it from the catalog.
        case catalog(CatalogItem)
    }

    public static func conflict(for name: String, editingItemID: UUID?, items: [ItemInfo]) -> Conflict {
        let k = key(name)
        guard !k.isEmpty else { return .none }
        let same = items.filter { $0.id != editingItemID && $0.allNames.contains { key($0) == k } }
        if let active = same.first(where: { !$0.isArchived }) { return .active(active) }
        if let archived = same.first { return .archived(archived) }
        if let fromCatalog = Catalog.items.first(where: { $0.allNames.contains { key($0) == k } }),
           !items.contains(where: { $0.id != editingItemID && $0.catalogKey == fromCatalog.key }) {
            return .catalog(fromCatalog)
        }
        return .none
    }

    /// Is this catalog item already in the user's list (active or archived)?
    public static func catalogItemInUse(_ key: String, items: [ItemInfo]) -> ItemInfo? {
        items.first { $0.catalogKey == key }
    }
}
