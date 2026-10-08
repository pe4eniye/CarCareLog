import XCTest
@testable import CarCareCore

final class CatalogTests: XCTestCase {
    func testCatalogIsConsistent() {
        let keys = Catalog.items.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count, "duplicate keys")
        XCTAssertEqual(Catalog.items.count, 58)
        for item in Catalog.items {
            XCTAssertFalse(item.uk.isEmpty || item.ru.isEmpty || item.en.isEmpty, item.key)
            XCTAssertLessThanOrEqual(item.uk.count, Limits.itemName, item.key)
            XCTAssertLessThanOrEqual(item.ru.count, Limits.itemName, item.key)
            XCTAssertLessThanOrEqual(item.en.count, Limits.itemName, item.key)
        }
        // Every category has items.
        for category in CatalogItem.Category.allCases {
            XCTAssertTrue(Catalog.items.contains { $0.category == category }, category.rawValue)
        }
        // Names are unique within each language.
        for lang in AssistantLanguage.allCases {
            let names = Catalog.items.map { ItemNameRules.key($0.name(lang)) }
            XCTAssertEqual(Set(names).count, names.count, lang.rawValue)
        }
    }

    func testCatalogNameFollowsLanguage() {
        XCTAssertEqual(Catalog.name("cabin_filter", .uk), "Фільтр салону")
        XCTAssertEqual(Catalog.name("cabin_filter", .ru), "Салонный фильтр")
        XCTAssertEqual(Catalog.name("cabin_filter", .en), "Cabin filter")
        XCTAssertNil(Catalog.name("nope", .en))
    }

    func testNameConflictsAcrossLanguagesAndCatalog() {
        let oil = ItemInfo(name: "Моторне масло", catalogKey: "engine_oil")
        // The same catalog item in another language counts as a duplicate.
        XCTAssertEqual(ItemNameRules.conflict(for: "engine oil", editingItemID: nil, items: [oil]), .active(oil))
        // A custom name equal to a catalog item not yet used: offer the catalog item.
        XCTAssertEqual(ItemNameRules.conflict(for: "салонный фильтр", editingItemID: nil, items: [oil]),
                       .catalog(Catalog.item("cabin_filter")!))
        XCTAssertEqual(ItemNameRules.conflict(for: "Масло Motul 8100", editingItemID: nil, items: [oil]), .none)
    }

    func testAssistantFindsCatalogItemInAnyLanguage() {
        let pads = ItemInfo(name: "Передні гальмівні колодки", intervalKm: 30_000, catalogKey: "front_pads")
        let entry = ServiceEntryInfo(date: TS.d(2026, 5, 1), odometerKm: 200_000, itemIDs: [pads.id])
        let snap = DataSnapshot(car: CarInfo(avgKmPerMonth: 1500), items: [pads], entries: [entry],
                                odometerReadings: [OdometerReadingInfo(date: TS.today, km: 210_000)])
        let ctx = AssistantContext(snapshot: snap, today: TS.today, calendar: TS.calendar, fallbackLanguage: .uk)
        for q in ["when did I change front brake pads?", "когда менял передние колодки?", "коли міняв колодки?"] {
            let r = Assistant.answer(q, context: ctx)
            XCTAssertEqual(r.intent, .lastDone, q)
            XCTAssertTrue(r.text.hasPrefix("Передні гальмівні колодки: "), q)
        }
    }
}

final class UrgencyAndEstimatorTests: XCTestCase {
    let cal = TS.calendar

    func testUrgencyColors() {
        let g = Garage()
        let statuses = ForecastEngine.statuses(for: g.snapshot, today: TS.today, calendar: cal)
        let current = g.snapshot.currentOdometerKm
        // Engine oil due 27 Oct 2026 (20 days): yellow.
        XCTAssertEqual(statuses[g.engineOil.id]?.forecast?.urgency(today: TS.today, calendar: cal,
                                                                  currentOdometerKm: current), .soon)
        // ATF due 15 May 2027: green.
        XCTAssertEqual(statuses[g.atf.id]?.forecast?.urgency(today: TS.today, calendar: cal,
                                                            currentOdometerKm: current), .ok)
        // Exactly 2 months ahead still counts as "soon"; overdue is red.
        var snap = g.snapshot
        snap.odometerReadings.append(OdometerReadingInfo(date: TS.d(2026, 10, 6), km: 231_000))
        let s2 = ForecastEngine.statuses(for: snap, today: TS.today, calendar: cal)
        XCTAssertEqual(s2[g.engineOil.id]?.forecast?.urgency(today: TS.today, calendar: cal,
                                                            currentOdometerKm: 231_000), .overdue)
        XCTAssertEqual(statuses[g.engineOil.id]?.forecast?.kmLeft(currentOdometerKm: current), 2_000)
    }

    func testMonthGroups() {
        let g = Garage()
        let statuses = ForecastEngine.statuses(for: g.snapshot, today: TS.today, calendar: cal)
        let groups = ForecastGroups.make(from: statuses, calendar: cal)
        XCTAssertEqual(groups.upcoming.map(\.month), [TS.d(2026, 10, 1), TS.d(2027, 1, 1), TS.d(2027, 5, 1),
                                                       TS.d(2028, 8, 1)])
        // ATF and spark plugs share May 2027.
        XCTAssertEqual(Set(groups.upcoming[2].forecasts.map(\.itemID)), Set([g.atf.id, g.plugs.id]))
    }

    func testScheduleSortedByUrgency() {
        let g = Garage()
        var snap = g.snapshot
        snap.odometerReadings.append(OdometerReadingInfo(date: TS.d(2026, 10, 6), km: 231_000))
        let statuses = ForecastEngine.statuses(for: snap, today: TS.today, calendar: cal)
        let sorted = ForecastEngine.urgencySorted(snap.activeItems, statuses: statuses).map(\.name)
        // Overdue first, then by date, items without records last.
        XCTAssertEqual(Array(sorted.prefix(3)).sorted(), ["Масляний фільтр", "Моторне масло", "Фільтри ГБО"])
        XCTAssertEqual(sorted[3], "Фільтр салону")
        XCTAssertEqual(sorted.last, "Повітряний фільтр")
    }

    func testEstimatorUsesManualUntilTwoMonthsOfData() {
        var snap = DataSnapshot(car: CarInfo(avgKmPerMonth: 1500))
        snap.odometerReadings = [OdometerReadingInfo(date: TS.d(2026, 9, 1), km: 100_000),
                                 OdometerReadingInfo(date: TS.d(2026, 10, 1), km: 102_000)]
        var e = MileageEstimator.estimate(snapshot: snap, today: TS.today, calendar: cal)
        XCTAssertFalse(e.isAutomatic)
        XCTAssertEqual(e.value, 1500)

        // 3 months of data: 6 080 km in 91 days ≈ 2 031 km/month.
        snap.odometerReadings.insert(OdometerReadingInfo(date: TS.d(2026, 7, 2), km: 95_920), at: 0)
        e = MileageEstimator.estimate(snapshot: snap, today: TS.today, calendar: cal)
        XCTAssertTrue(e.isAutomatic)
        XCTAssertEqual(e.spanDays, 91)
        XCTAssertEqual(e.value, 2031)

        // Service entries count too, and points older than 6 months are ignored.
        snap.entries = [ServiceEntryInfo(date: TS.d(2025, 1, 1), odometerKm: 10_000, itemIDs: [UUID()])]
        XCTAssertEqual(MileageEstimator.estimate(snapshot: snap, today: TS.today, calendar: cal).value, 2031)
    }

    func testEstimatorChangesTheForecast() {
        let oil = ItemInfo(name: "Oil", intervalKm: 10_000)
        var snap = DataSnapshot(car: CarInfo(avgKmPerMonth: 304), items: [oil],
                                entries: [ServiceEntryInfo(date: TS.d(2026, 7, 9), odometerKm: 100_000, itemIDs: [oil.id])],
                                odometerReadings: [OdometerReadingInfo(date: TS.d(2026, 10, 7), km: 109_100)])
        // Entry 9 Jul at 100 000, reading 7 Oct at 109 100: 90 days → ≈ 3 073 km/month, not the manual 304.
        let f = ForecastEngine.statuses(for: snap, today: TS.today, calendar: cal)[oil.id]?.forecast
        XCTAssertNotNil(f?.dueDate)
        XCTAssertLessThan(f!.dueDate!, TS.d(2026, 10, 20))
        snap.odometerReadings = []
        let manual = ForecastEngine.statuses(for: snap, today: TS.today, calendar: cal)[oil.id]?.forecast
        XCTAssertGreaterThan(manual!.dueDate!, TS.d(2027, 1, 1))
    }
}
