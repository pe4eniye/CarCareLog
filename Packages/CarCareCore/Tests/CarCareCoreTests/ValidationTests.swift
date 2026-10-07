import XCTest
@testable import CarCareCore

final class ValidationTests: XCTestCase {
    func testItemNamesAreUniqueIgnoringCaseSpacesAndYo() {
        let oil = ItemInfo(name: "Моторне масло")
        let old = ItemInfo(name: "Фільтр салону", isArchived: true)
        let items = [oil, old]
        XCTAssertEqual(ItemNameRules.conflict(for: "  моторне   МАСЛО ", editingItemID: nil, items: items), .active(oil))
        XCTAssertEqual(ItemNameRules.key("Тёплый  Салон"), ItemNameRules.key("теплый салон"))
        // Renaming an item to its own name is fine.
        XCTAssertEqual(ItemNameRules.conflict(for: "Моторне масло", editingItemID: oil.id, items: items), .none)
        // Similar but different names are allowed.
        XCTAssertEqual(ItemNameRules.conflict(for: "Моторне масло 5W-30", editingItemID: nil, items: items), .none)
        // Only an archived item has this name: offer restore.
        XCTAssertEqual(ItemNameRules.conflict(for: "фільтр салону", editingItemID: nil, items: items), .archived(old))
        XCTAssertEqual(ItemNameRules.conflict(for: "   ", editingItemID: nil, items: items), .none)
    }

    func testFieldRules() {
        XCTAssertEqual(ValidationRules.text("  ", required: true, max: 40), .required)
        XCTAssertEqual(ValidationRules.text(String(repeating: "a", count: 41), required: true, max: 40), .tooLong(max: 40))
        XCTAssertNil(ValidationRules.text("", required: false, max: 40))
        XCTAssertEqual(ValidationRules.number(nil, required: true, range: Limits.avgKmPerMonth), .required)
        XCTAssertNil(ValidationRules.number(nil, required: false, range: Limits.intervalKm))
        XCTAssertEqual(ValidationRules.number(50, required: false, range: Limits.intervalKm),
                       .outOfRange(min: 100, max: 500_000))
        XCTAssertNil(ValidationRules.number(8_000, required: false, range: Limits.intervalKm))
        XCTAssertEqual(ValidationRules.pastOrToday(nil, now: TS.today, calendar: TS.calendar), .required)
        XCTAssertEqual(ValidationRules.pastOrToday(TS.d(2026, 10, 8), now: TS.today, calendar: TS.calendar), .dateInFuture)
        XCTAssertNil(ValidationRules.pastOrToday(TS.d(2026, 10, 7, 23), now: TS.today, calendar: TS.calendar))
    }
}

final class HorizonAndHistoryTests: XCTestCase {
    func testHomeHorizon12MonthsOr15000Km() {
        let g = Garage()
        var snap = g.snapshot
        // Timing belt: due in 2029 by time and 290 000 km by mileage, far beyond both limits.
        let belt = ItemInfo(name: "Ремінь ГРМ", intervalKm: 90_000, intervalMonths: 60)
        snap.items.append(belt)
        snap.entries.append(ServiceEntryInfo(date: TS.d(2024, 6, 10), odometerKm: 200_000, itemIDs: [belt.id]))
        let statuses = ForecastEngine.statuses(for: snap, today: TS.today, calendar: TS.calendar)
        let groups = ForecastGroups.make(from: statuses, calendar: TS.calendar, today: TS.today,
                                         currentOdometerKm: snap.currentOdometerKm)
        let upcomingIDs = groups.upcoming.flatMap { $0.forecasts.map(\.itemID) }
        let laterIDs = groups.later.flatMap { $0.forecasts.map(\.itemID) }
        XCTAssertTrue(laterIDs.contains(belt.id))
        XCTAssertFalse(upcomingIDs.contains(belt.id))
        // ATF: 15 May 2027 is within 12 months → upcoming.
        XCTAssertTrue(upcomingIDs.contains(g.atf.id))
        // Brake fluid: 20 Aug 2028 is beyond 12 months, and its projected km is beyond +15 000 → later.
        XCTAssertTrue(laterIDs.contains(g.brakeFluid.id))

        // Without a horizon everything stays upcoming (widget, assistant).
        let all = ForecastGroups.make(from: statuses, calendar: TS.calendar)
        XCTAssertTrue(all.later.isEmpty)
    }

    func testHistoryKeepsRecordedNamesAfterRename() {
        let g = Garage()
        var snap = g.snapshot
        let oilIndex = snap.items.firstIndex { $0.id == g.engineOil.id }!
        // The 2025 entry recorded "Моторне масло"; the item was later renamed.
        snap.entries[0].itemNames = ["Моторне масло", "Масляний фільтр", "Фільтри ГБО"]
        snap.items[oilIndex].name = "Гальмівні диски"
        let ctx = AssistantContext(snapshot: snap, today: TS.today, calendar: TS.calendar, fallbackLanguage: .uk)
        let r = Assistant.answer("що я міняв у 2025 році?", context: ctx)
        XCTAssertEqual(TS.plain(r.lines[1].text),
                       "3 листопада 2025 · 220 000 км — Моторне масло, Масляний фільтр, Фільтри ГБО")
    }

    func testArchivedItemInAssistant() {
        let g = Garage()
        var snap = g.snapshot
        let i = snap.items.firstIndex { $0.id == g.lpg.id }!
        snap.items[i].isArchived = true
        let ctx = AssistantContext(snapshot: snap, today: TS.today, calendar: TS.calendar, fallbackLanguage: .uk)
        XCTAssertEqual(TS.plain(Assistant.answer("коли міняти фільтри ГБО?", context: ctx).text),
                       "Фільтри ГБО: позиція в архіві, прогноз не ведеться.")
        // Its history is still there.
        XCTAssertEqual(TS.plain(Assistant.answer("коли мінялися фільтри ГБО?", context: ctx).text),
                       "Фільтри ГБО: 220 000 км (3 листопада 2025)")
        // And it is not in the "due at" list.
        let due = Assistant.answer("що замінити на 250 тис?", context: ctx)
        XCTAssertFalse(due.text.contains("Фільтри ГБО"))
    }
}
