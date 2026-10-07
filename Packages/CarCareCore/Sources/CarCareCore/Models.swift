import Foundation

// Plain value types used by all business logic. The app maps its SwiftData
// models to these, so everything here can be unit-tested without iOS.

public struct CarInfo: Codable, Equatable {
    public var id: UUID
    public var make: String
    public var model: String
    public var year: Int?
    public var vin: String?
    public var avgKmPerMonth: Double

    public init(id: UUID = UUID(), make: String = "", model: String = "", year: Int? = nil,
                vin: String? = nil, avgKmPerMonth: Double = 1000) {
        self.id = id
        self.make = make
        self.model = model
        self.year = year
        self.vin = vin
        self.avgKmPerMonth = avgKmPerMonth
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

    public init(id: UUID = UUID(), name: String, aliases: [String] = [], intervalKm: Int? = nil,
                intervalMonths: Int? = nil, oemNumber: String? = nil, analogNumbers: [String] = []) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.intervalKm = intervalKm
        self.intervalMonths = intervalMonths
        self.oemNumber = oemNumber
        self.analogNumbers = analogNumbers
    }

    public var hasInterval: Bool {
        (intervalKm ?? 0) > 0 || (intervalMonths ?? 0) > 0
    }
}

public struct ServiceEntryInfo: Codable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    public var odometerKm: Int
    public var itemIDs: [UUID]

    public init(id: UUID = UUID(), date: Date, odometerKm: Int, itemIDs: [UUID]) {
        self.id = id
        self.date = date
        self.odometerKm = odometerKm
        self.itemIDs = itemIDs
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

    public var currentOdometerKm: Int? {
        OdometerRules.current(readings: odometerReadings)?.km
    }

    public func item(id: UUID) -> ItemInfo? {
        items.first { $0.id == id }
    }
}
