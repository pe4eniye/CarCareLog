import Foundation
import SwiftData
import CarCareCore

// SwiftData models. CloudKit rules: every property has a default or is optional,
// no unique constraints, relationships optional with inverses, no stored enums.

@Model
final class Car {
    var uuid: UUID = UUID()
    var name: String = ""
    var vin: String?
    var avgKmPerMonth: Double = 1000
    var createdAt: Date = Date()

    init(name: String = "", vin: String? = nil, avgKmPerMonth: Double = 1000) {
        self.name = name
        self.vin = vin
        self.avgKmPerMonth = avgKmPerMonth
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
    var isArchived: Bool = false
    var createdAt: Date = Date()
    var entries: [ServiceEntry]? = []

    init(name: String) {
        self.name = name
    }
}

/// The name of an item as it was when the entry was recorded.
struct EntryItemSnapshot: Codable, Hashable {
    var itemID: UUID
    var name: String
}

@Model
final class ServiceEntry {
    var uuid: UUID = UUID()
    var date: Date = Date()
    var odometerKm: Int = 0
    /// Live link, used for forecasts.
    @Relationship(deleteRule: .nullify, inverse: \Item.entries)
    var items: [Item]? = []
    /// What History shows. Survives renaming and deleting items.
    var snapshot: [EntryItemSnapshot] = []
    var createdAt: Date = Date()

    init(date: Date, odometerKm: Int, items: [Item]) {
        self.date = date
        self.odometerKm = odometerKm
        setItems(items)
    }

    /// Sets the linked items. Names already recorded for kept items stay as they were.
    func setItems(_ newItems: [Item]) {
        let old = Dictionary(snapshot.map { ($0.itemID, $0.name) }, uniquingKeysWith: { a, _ in a })
        let liveBefore = Set((items ?? []).map(\.uuid))
        let newIDs = Set(newItems.map(\.uuid))
        // Items deleted since the entry was recorded are no longer linked; keep their recorded names.
        // Linked items the user unticked are dropped.
        let deleted = snapshot.filter { !liveBefore.contains($0.itemID) && !newIDs.contains($0.itemID) }
        items = newItems
        snapshot = deleted + newItems.map { EntryItemSnapshot(itemID: $0.uuid, name: old[$0.uuid] ?? $0.name) }
    }

    /// Names to show in History, alphabetically.
    var displayNames: [String] {
        let names = snapshot.isEmpty ? (items ?? []).map(\.name) : snapshot.map(\.name)
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
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
    var info: CarInfo { CarInfo(id: uuid, name: name, vin: vin, avgKmPerMonth: avgKmPerMonth) }
}

extension Item {
    var info: ItemInfo {
        ItemInfo(id: uuid, name: name, aliases: aliases, intervalKm: intervalKm, intervalMonths: intervalMonths,
                 oemNumber: oemNumber, analogNumbers: analogNumbers, isArchived: isArchived)
    }
}

extension ServiceEntry {
    var info: ServiceEntryInfo {
        if snapshot.isEmpty {
            let list = items ?? []
            return ServiceEntryInfo(id: uuid, date: date, odometerKm: odometerKm, itemIDs: list.map(\.uuid),
                                    itemNames: list.map(\.name))
        }
        return ServiceEntryInfo(id: uuid, date: date, odometerKm: odometerKm, itemIDs: snapshot.map(\.itemID),
                                itemNames: snapshot.map(\.name))
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
            let car = Car(name: c.name, vin: c.vin, avgKmPerMonth: c.avgKmPerMonth)
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
            item.isArchived = i.isArchived
            // Keeps the original list order.
            item.createdAt = Date(timeIntervalSince1970: TimeInterval(index))
            context.insert(item)
            byID[i.id] = item
        }
        for e in snapshot.entries {
            let entry = ServiceEntry(date: e.date, odometerKm: e.odometerKm, items: e.itemIDs.compactMap { byID[$0] })
            entry.uuid = e.id
            let names = e.displayNames(items: snapshot.items)
            entry.snapshot = zip(e.itemIDs, names).map { EntryItemSnapshot(itemID: $0, name: $1) }
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

/// Item operations shared by the editor and the lists.
@MainActor
enum ItemActions {
    /// "Fix a typo": rename the item and the names recorded in its history.
    static func renameEverywhere(_ item: Item, to newName: String) {
        item.name = newName
        for entry in item.entries ?? [] {
            entry.snapshot = entry.snapshot.map { $0.itemID == item.uuid ? EntryItemSnapshot(itemID: $0.itemID, name: newName) : $0 }
        }
    }

    static func hasHistory(_ item: Item) -> Bool { !(item.entries ?? []).isEmpty }
}
