import XCTest
import SwiftData
import CarCareCore
@testable import CarCareLog

@MainActor
final class AppSmokeTests: XCTestCase {
    func testLocalizationBundlesLoad() {
        L10n.setLanguage("en")
        XCTAssertEqual(L10n.t("tab.home"), "Home")
        XCTAssertEqual(L10n.f("widget.overdue", 2), "Overdue: 2")
        L10n.setLanguage("ru")
        XCTAssertEqual(L10n.t("tab.home"), "Главная")
        XCTAssertEqual(L10n.assistantLanguage, .ru)
        XCTAssertEqual(Fmt.km(220_000), "220\u{00A0}000\u{00A0}км")
        L10n.setLanguage("uk")
        XCTAssertEqual(L10n.t("tab.home"), "Головна")
        XCTAssertEqual(L10n.f("item.duplicateLine", "A1", "Масло"), "A1 вже є у «Масло»")
    }

    func testSwiftDataMappingAndRestoreRoundTrip() throws {
        let persistence = Persistence(inMemory: true)
        let context = persistence.container.mainContext

        let oil = Item(name: "Моторне масло")
        oil.intervalKm = 10_000
        oil.oemNumber = "06L 115 562"
        oil.analogNumbers = ["W 719/45"]
        let filter = Item(name: "Фільтр салону")
        filter.createdAt = oil.createdAt.addingTimeInterval(1)
        context.insert(oil)
        context.insert(filter)
        context.insert(Car(name: "Skoda Octavia", avgKmPerMonth: 1500))
        context.insert(ServiceEntry(date: Date(timeIntervalSince1970: 1_780_000_000), odometerKm: 220_000,
                                    items: [oil, filter]))
        context.insert(OdometerReading(date: Date(timeIntervalSince1970: 1_780_000_000), km: 220_000))
        try context.save()

        let before = SnapshotBuilder.fetch(context)
        XCTAssertEqual(before.items.map(\.name), ["Моторне масло", "Фільтр салону"])
        XCTAssertEqual(Set(before.entries.first?.itemIDs ?? []), Set([oil.uuid, filter.uuid]))

        let data = try BackupCodec.encode(before, exportedAt: Date())
        let file = try BackupCodec.decode(data)

        // Restore into a fresh store and compare.
        let other = Persistence(inMemory: true)
        try SnapshotBuilder.restore(file.snapshot, into: other.container.mainContext)
        let after = SnapshotBuilder.fetch(other.container.mainContext)
        XCTAssertEqual(after.car, before.car)
        XCTAssertEqual(after.items, before.items)
        XCTAssertEqual(after.odometerReadings, before.odometerReadings)
        XCTAssertEqual(after.entries.count, 1)
        XCTAssertEqual(Set(after.entries[0].itemIDs), Set(before.entries[0].itemIDs))

        // Restoring again replaces instead of duplicating.
        try SnapshotBuilder.restore(file.snapshot, into: other.container.mainContext)
        XCTAssertEqual(SnapshotBuilder.fetch(other.container.mainContext).items.count, 2)
    }

    func testHistoryKeepsRecordedNamesAfterRenameAndDelete() throws {
        let persistence = Persistence(inMemory: true)
        let context = persistence.container.mainContext
        let oil = Item(name: "Масло")
        let pads = Item(name: "Колодки")
        context.insert(oil)
        context.insert(pads)
        let entry = ServiceEntry(date: Date(timeIntervalSince1970: 1_780_000_000), odometerKm: 150_000, items: [oil, pads])
        context.insert(entry)
        try context.save()

        // Renamed as "a different part": history keeps the old name.
        oil.name = "Гальмівні диски"
        XCTAssertEqual(entry.displayNames, ["Колодки", "Масло"])

        // "Fix a typo": history follows.
        ItemActions.renameEverywhere(pads, to: "Колодки передні")
        XCTAssertEqual(entry.displayNames, ["Колодки передні", "Масло"])

        // Deleting an item keeps its name in history, also after editing the entry.
        context.delete(pads)
        try context.save()
        XCTAssertEqual(entry.displayNames, ["Колодки передні", "Масло"])
        entry.setItems(entry.items ?? [])
        XCTAssertEqual(entry.displayNames, ["Колодки передні", "Масло"])
        // Unticking a live item removes it.
        entry.setItems([])
        XCTAssertEqual(entry.displayNames, ["Колодки передні"])
    }
}
