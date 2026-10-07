import Foundation
import SwiftData
import CarCareCore

// SwiftData models. CloudKit rules: every property has a default or is optional,
// no unique constraints, relationships optional with inverses, no stored enums.

@Model
final class Car {
    var uuid: UUID = UUID()
    var make: String = ""
    var model: String = ""
    var year: Int?
    var vin: String?
    var avgKmPerMonth: Double = 1000
    var createdAt: Date = Date()

    init(make: String = "", model: String = "", year: Int? = nil, vin: String? = nil, avgKmPerMonth: Double = 1000) {
        self.make = make
        self.model = model
        self.year = year
        self.vin = vin
        self.avgKmPerMonth = avgKmPerMonth
    }

    var displayName: String {
        [make, model].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

@Model
final class Item {
    var uuid: UUID = UUID()
    var name: String = ""
    var aliases: [String] = []
    var intervalKm: Int?
    var intervalMonths: Int?
    var oemNumber: String?
    var analogNumbers: [String] = []
    var createdAt: Date = Date()
    var entries: [ServiceEntry]? = []

    init(name: String) {
        self.name = name
    }
}

@Model
final class ServiceEntry {
    var uuid: UUID = UUID()
    var date: Date = Date()
    var odometerKm: Int = 0
    @Relationship(deleteRule: .nullify, inverse: \Item.entries)
    var items: [Item]? = []
    var createdAt: Date = Date()

    init(date: Date, odometerKm: Int, items: [Item]) {
        self.date = date
        self.odometerKm = odometerKm
        self.items = items
    }

    var sortedItems: [Item] {
        (items ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

@Model
final class OdometerReading {
    var uuid: UUID = UUID()
    var date: Date = Date()
    var km: Int = 0

    init(date: Date, km: Int) {
        self.date = date
        self.km = km
    }
}

// MARK: - Mapping to CarCareCore values

extension Car {
    var info: CarInfo {
        CarInfo(id: uuid, make: make, model: model, year: year, vin: vin, avgKmPerMonth: avgKmPerMonth)
    }
}

extension Item {
    var info: ItemInfo {
        ItemInfo(id: uuid, name: name, aliases: aliases, intervalKm: intervalKm, intervalMonths: intervalMonths,
                 oemNumber: oemNumber, analogNumbers: analogNumbers)
    }
}

extension ServiceEntry {
    var info: ServiceEntryInfo {
        ServiceEntryInfo(id: uuid, date: date, odometerKm: odometerKm, itemIDs: (items ?? []).map(\.uuid))
    }
}

extension OdometerReading {
    var info: OdometerReadingInfo { OdometerReadingInfo(id: uuid, date: date, km: km) }
}

enum SnapshotBuilder {
    static func make(cars: [Car], items: [Item], entries: [ServiceEntry], readings: [OdometerReading]) -> DataSnapshot {
        DataSnapshot(car: primaryCar(cars)?.info, items: items.map(\.info), entries: entries.map(\.info),
                     odometerReadings: readings.map(\.info))
    }

    static func fetch(_ context: ModelContext) -> DataSnapshot {
        let cars = (try? context.fetch(FetchDescriptor<Car>())) ?? []
        let items = (try? context.fetch(FetchDescriptor<Item>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let entries = (try? context.fetch(FetchDescriptor<ServiceEntry>())) ?? []
        let readings = (try? context.fetch(FetchDescriptor<OdometerReading>())) ?? []
        return make(cars: cars, items: items, entries: entries, readings: readings)
    }

    /// MVP supports one car. If iCloud sync ever produces two, the oldest wins.
    static func primaryCar(_ cars: [Car]) -> Car? {
        cars.min { $0.createdAt < $1.createdAt }
    }

    /// Replaces everything in the store with the backup contents.
    static func restore(_ snapshot: DataSnapshot, into context: ModelContext) throws {
        // Deleting one by one is slower than a batch delete but safe with relationships.
        for e in try context.fetch(FetchDescriptor<ServiceEntry>()) { context.delete(e) }
        for i in try context.fetch(FetchDescriptor<Item>()) { context.delete(i) }
        for r in try context.fetch(FetchDescriptor<OdometerReading>()) { context.delete(r) }
        for c in try context.fetch(FetchDescriptor<Car>()) { context.delete(c) }
        try context.save()

        if let c = snapshot.car {
            let car = Car(make: c.make, model: c.model, year: c.year, vin: c.vin, avgKmPerMonth: c.avgKmPerMonth)
            car.uuid = c.id
            context.insert(car)
        }
        var byID: [UUID: Item] = [:]
        for (index, i) in snapshot.items.enumerated() {
            let item = Item(name: i.name)
            item.uuid = i.id
            item.aliases = i.aliases
            item.intervalKm = i.intervalKm
            item.intervalMonths = i.intervalMonths
            item.oemNumber = i.oemNumber
            item.analogNumbers = i.analogNumbers
            // Keeps the original list order.
            item.createdAt = Date(timeIntervalSince1970: TimeInterval(index))
            context.insert(item)
            byID[i.id] = item
        }
        for e in snapshot.entries {
            let entry = ServiceEntry(date: e.date, odometerKm: e.odometerKm, items: e.itemIDs.compactMap { byID[$0] })
            entry.uuid = e.id
            context.insert(entry)
        }
        for r in snapshot.odometerReadings {
            let reading = OdometerReading(date: r.date, km: r.km)
            reading.uuid = r.id
            context.insert(reading)
        }
        try context.save()
    }
}
