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

    public init(id: UUID = UUID(), name: String, aliases: [String] = [], intervalKm: Int? = nil,
                intervalMonths: Int? = nil, oemNumber: String? = nil, analogNumbers: [String] = [],
                isArchived: Bool = false, catalogKey: String? = nil) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.intervalKm = intervalKm
        self.intervalMonths = intervalMonths
        self.oemNumber = oemNumber
        self.analogNumbers = analogNumbers
        self.isArchived = isArchived
        self.catalogKey = catalogKey
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
    }

    public var catalogItem: CatalogItem? { Catalog.item(catalogKey) }

    /// Names in all three languages for catalog items, otherwise the custom name.
    public var allNames: [String] { catalogItem?.allNames ?? [name] }

    public var hasInterval: Bool {
        (intervalKm ?? 0) > 0 || (intervalMonths ?? 0) > 0
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

    public init(id: UUID = UUID(), date: Date, odometerKm: Int, itemIDs: [UUID], itemNames: [String] = [],
                itemCatalogKeys: [String] = []) {
        self.id = id
        self.date = date
        self.odometerKm = odometerKm
        self.itemIDs = itemIDs
        self.itemNames = itemNames
        self.itemCatalogKeys = itemCatalogKeys
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        odometerKm = try c.decode(Int.self, forKey: .odometerKm)
        itemIDs = try c.decode([UUID].self, forKey: .itemIDs)
        itemNames = try c.decodeIfPresent([String].self, forKey: .itemNames) ?? []
        itemCatalogKeys = try c.decodeIfPresent([String].self, forKey: .itemCatalogKeys) ?? []
    }

    /// Recorded names, falling back to the current item name for entries without a snapshot.
    public func displayNames(items: [ItemInfo]) -> [String] {
        itemIDs.enumerated().compactMap { index, id in
            if index < itemNames.count, !itemNames[index].isEmpty { return itemNames[index] }
            return items.first { $0.id == id }?.name
        }
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
