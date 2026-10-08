import Foundation

// Plain value types used by all business logic. The app maps its SwiftData
// models to these, so everything here can be unit-tested without iOS.

public struct CarInfo: Codable, Equatable {
    public var id: UUID
    /// Any name the user likes: "Octavia", "Синя".
    public var name: String
    public var vin: String?
    public var avgKmPerMonth: Double

    public init(id: UUID = UUID(), name: String = "", vin: String? = nil, avgKmPerMonth: Double = 1000) {
        self.id = id
        self.name = name
        self.vin = vin
        self.avgKmPerMonth = avgKmPerMonth
    }

    enum CodingKeys: String, CodingKey {
        case id, name, vin, avgKmPerMonth
        case make, model, year // backup format 1
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        vin = try c.decodeIfPresent(String.self, forKey: .vin)
        avgKmPerMonth = try c.decode(Double.self, forKey: .avgKmPerMonth)
        if let n = try c.decodeIfPresent(String.self, forKey: .name) {
            name = n
        } else {
            let make = try c.decodeIfPresent(String.self, forKey: .make) ?? ""
            let model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
            name = [make, model].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(vin, forKey: .vin)
        try c.encode(avgKmPerMonth, forKey: .avgKmPerMonth)
    }
}

/// How an item's next date is found.
public enum ItemKind: String, Codable, CaseIterable {
    /// Every N km and/or N months after the last replacement (oil, filters…).
    case interval
    /// Valid until a date (insurance, inspection).
    case expiry
    /// In fixed months of the year (seasonal tire change: April and October).
    case seasonal
}

public struct ItemInfo: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var aliases: [String]
    public var intervalKm: Int?
    public var intervalMonths: Int?
    public var oemNumber: String?
    public var analogNumbers: [String]
    /// Archived items keep their history but get no forecast and no reminders.
    public var isArchived: Bool
    /// Set for items added from the built-in catalog: their name follows the app language.
    public var catalogKey: String?
    public var kind: ItemKind
    /// Months 1…12 for seasonal items.
    public var seasonMonths: [Int]
    /// End date for expiry items (e.g. the insurance policy is valid until…).
    public var validUntil: Date?

    public init(id: UUID = UUID(), name: String, aliases: [String] = [], intervalKm: Int? = nil,
                intervalMonths: Int? = nil, oemNumber: String? = nil, analogNumbers: [String] = [],
                isArchived: Bool = false, catalogKey: String? = nil, kind: ItemKind = .interval,
                seasonMonths: [Int] = [], validUntil: Date? = nil) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.intervalKm = intervalKm
        self.intervalMonths = intervalMonths
        self.oemNumber = oemNumber
        self.analogNumbers = analogNumbers
        self.isArchived = isArchived
        self.catalogKey = catalogKey
        self.kind = kind
        self.seasonMonths = seasonMonths
        self.validUntil = validUntil
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        intervalKm = try c.decodeIfPresent(Int.self, forKey: .intervalKm)
        intervalMonths = try c.decodeIfPresent(Int.self, forKey: .intervalMonths)
        oemNumber = try c.decodeIfPresent(String.self, forKey: .oemNumber)
        analogNumbers = try c.decodeIfPresent([String].self, forKey: .analogNumbers) ?? []
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        catalogKey = try c.decodeIfPresent(String.self, forKey: .catalogKey)
        kind = try c.decodeIfPresent(ItemKind.self, forKey: .kind) ?? .interval
        seasonMonths = try c.decodeIfPresent([Int].self, forKey: .seasonMonths) ?? []
        validUntil = try c.decodeIfPresent(Date.self, forKey: .validUntil)
    }

    public var catalogItem: CatalogItem? { Catalog.item(catalogKey) }

    /// Names in all three languages for catalog items, otherwise the custom name.
    public var allNames: [String] { catalogItem?.allNames ?? [name] }

    /// Enough settings to compute a next date: km or months for intervals, months for seasonal items.
    /// Expiry items always qualify (without a date they show "no date set").
    public var hasInterval: Bool {
        switch kind {
        case .interval: return (intervalKm ?? 0) > 0 || (intervalMonths ?? 0) > 0
        case .expiry: return true
        case .seasonal: return seasonMonths.contains { (1...12).contains($0) }
        }
    }
}

public enum Currency: String, Codable, CaseIterable {
    case uah = "UAH", usd = "USD", eur = "EUR"

    public var symbol: String {
        switch self {
        case .uah: return "₴"
        case .usd: return "$"
        case .eur: return "€"
        }
    }
}

public struct ServiceEntryInfo: Codable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    public var odometerKm: Int
    public var itemIDs: [UUID]
    /// Item names as they were when the entry was recorded, same order as itemIDs.
    /// History shows these, so renaming or deleting an item never rewrites the past.
    public var itemNames: [String]
    /// Catalog keys of the items, same order ("" for custom items), so names can follow the app language.
    public var itemCatalogKeys: [String]
    /// Optional price per item, same order as itemIDs ("split by item").
    public var itemCosts: [Double?]
    /// Optional total for the whole entry (the sum of itemCosts when split).
    public var costTotal: Double?
    /// Currency the entry was recorded in; totals are never mixed across currencies.
    public var currency: Currency
    public var note: String

    public init(id: UUID = UUID(), date: Date, odometerKm: Int, itemIDs: [UUID], itemNames: [String] = [],
                itemCatalogKeys: [String] = [], itemCosts: [Double?] = [], costTotal: Double? = nil,
                currency: Currency = .uah, note: String = "") {
        self.id = id
        self.date = date
        self.odometerKm = odometerKm
        self.itemIDs = itemIDs
        self.itemNames = itemNames
        self.itemCatalogKeys = itemCatalogKeys
        self.itemCosts = itemCosts
        self.costTotal = costTotal
        self.currency = currency
        self.note = note
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        odometerKm = try c.decode(Int.self, forKey: .odometerKm)
        itemIDs = try c.decode([UUID].self, forKey: .itemIDs)
        itemNames = try c.decodeIfPresent([String].self, forKey: .itemNames) ?? []
        itemCatalogKeys = try c.decodeIfPresent([String].self, forKey: .itemCatalogKeys) ?? []
        itemCosts = try c.decodeIfPresent([Double?].self, forKey: .itemCosts) ?? []
        costTotal = try c.decodeIfPresent(Double.self, forKey: .costTotal)
        currency = try c.decodeIfPresent(Currency.self, forKey: .currency) ?? .uah
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    /// Recorded names, falling back to the current item name for entries without a snapshot.
    public func displayNames(items: [ItemInfo]) -> [String] {
        itemIDs.enumerated().compactMap { index, id in
            if index < itemNames.count, !itemNames[index].isEmpty { return itemNames[index] }
            return items.first { $0.id == id }?.name
        }
    }

    /// Price of one item in this entry: its own price when split, or the total when it was the only item.
    public func cost(of itemID: UUID) -> Double? {
        guard let index = itemIDs.firstIndex(of: itemID) else { return nil }
        if index < itemCosts.count, let c = itemCosts[index] { return c }
        if itemIDs.count == 1 { return costTotal }
        return nil
    }
}

public struct OdometerReadingInfo: Codable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    public var km: Int

    public init(id: UUID = UUID(), date: Date, km: Int) {
        self.id = id
        self.date = date
        self.km = km
    }
}

/// Everything the app knows, as plain values. Used by forecast, assistant and backup.
public struct DataSnapshot: Codable, Equatable {
    public var car: CarInfo?
    public var items: [ItemInfo]
    public var entries: [ServiceEntryInfo]
    public var odometerReadings: [OdometerReadingInfo]

    public init(car: CarInfo? = nil, items: [ItemInfo] = [], entries: [ServiceEntryInfo] = [],
                odometerReadings: [OdometerReadingInfo] = []) {
        self.car = car
        self.items = items
        self.entries = entries
        self.odometerReadings = odometerReadings
    }

    /// Latest known odometer from readings and service entries together.
    public var currentOdometer: OdometerReadingInfo? {
        OdometerRules.current(readings: odometerReadings, entries: entries)
    }

    public var currentOdometerKm: Int? { currentOdometer?.km }

    public var activeItems: [ItemInfo] { items.filter { !$0.isArchived } }

    public func item(id: UUID) -> ItemInfo? {
        items.first { $0.id == id }
    }
}
