import XCTest
@testable import CarCareCore

final class ItemKindTests: XCTestCase {
    let cal = TS.calendar

    func testExpiryItem() {
        let insurance = ItemInfo(name: "Страховка", catalogKey: "insurance", kind: .expiry,
                                 validUntil: TS.d(2026, 11, 15))
        let s = ForecastEngine.status(for: insurance, entries: [], currentOdometerKm: 228_000, avgKmPerMonth: 3040,
                                      today: TS.today, calendar: cal)
        let f = s.forecast!
        XCTAssertEqual(f.dueDate, TS.d(2026, 11, 15))
        XCTAssertEqual(f.reason, .time)
        XCTAssertNil(f.dueKm)
        XCTAssertFalse(f.isOverdue)
        XCTAssertEqual(f.daysLeft(today: TS.today, calendar: cal), 39)
        XCTAssertEqual(f.urgency(today: TS.today, calendar: cal, currentOdometerKm: 228_000), .soon)
        // Expired.
        let late = ForecastEngine.status(for: insurance, entries: [], currentOdometerKm: 228_000, avgKmPerMonth: 3040,
                                         today: TS.d(2026, 11, 20), calendar: cal)
        XCTAssertEqual(late.forecast?.isOverdue, true)
        // No date yet.
        var noDate = insurance
        noDate.validUntil = nil
        XCTAssertEqual(ForecastEngine.status(for: noDate, entries: [], currentOdometerKm: nil, avgKmPerMonth: 0,
                                             today: TS.today, calendar: cal), .noHistory)
    }

    func testSeasonalItem() {
        let tires = ItemInfo(name: "Шини", catalogKey: "seasonal_tires", kind: .seasonal, seasonMonths: [4, 10])
        // Done in April: next is October (this month) → due 1 Oct, not overdue in October.
        let april = ServiceEntryInfo(date: TS.d(2026, 4, 12), odometerKm: 220_000, itemIDs: [tires.id])
        var f = ForecastEngine.status(for: tires, entries: [april], currentOdometerKm: 228_000, avgKmPerMonth: 3040,
                                      today: TS.today, calendar: cal).forecast!
        XCTAssertEqual(f.dueDate, TS.d(2026, 10, 1))
        XCTAssertFalse(f.isOverdue)
        // Still not done in November: overdue.
        f = ForecastEngine.status(for: tires, entries: [april], currentOdometerKm: 228_000, avgKmPerMonth: 3040,
                                  today: TS.d(2026, 11, 3), calendar: cal).forecast!
        XCTAssertTrue(f.isOverdue)
        // Done in October: next is April.
        let october = ServiceEntryInfo(date: TS.d(2026, 10, 5), odometerKm: 228_000, itemIDs: [tires.id])
        f = ForecastEngine.status(for: tires, entries: [april, october], currentOdometerKm: 228_000, avgKmPerMonth: 3040,
                                  today: TS.today, calendar: cal).forecast!
        XCTAssertEqual(f.dueDate, TS.d(2027, 4, 1))
        // No records: the next season month from now.
        f = ForecastEngine.status(for: tires, entries: [], currentOdometerKm: nil, avgKmPerMonth: 0,
                                  today: TS.d(2026, 7, 1), calendar: cal).forecast!
        XCTAssertEqual(f.dueDate, TS.d(2026, 10, 1))
    }

    func testCatalogDefaults() {
        XCTAssertEqual(Catalog.item("insurance")?.kind, .expiry)
        XCTAssertEqual(Catalog.item("inspection")?.kind, .expiry)
        XCTAssertEqual(Catalog.item("seasonal_tires")?.kind, .seasonal)
        XCTAssertEqual(Catalog.item("seasonal_tires")?.seasonMonths, [4, 10])
        XCTAssertEqual(Catalog.item("engine_oil")?.kind, .interval)
    }

    func testIntervalNeedsKmOrMonths() {
        XCTAssertFalse(ItemInfo(name: "x").hasInterval)
        XCTAssertTrue(ItemInfo(name: "x", intervalMonths: 6).hasInterval)
        XCTAssertFalse(ItemInfo(name: "x", kind: .seasonal).hasInterval)
        XCTAssertTrue(ItemInfo(name: "x", kind: .expiry).hasInterval)
    }

    func testRemindersAtCustomTimeAndNudgeInterval() {
        let g = Garage()
        let statuses = ForecastEngine.statuses(for: g.snapshot, today: TS.today, calendar: cal)
        let plan = ReminderPlanner.plan(statuses: statuses, items: g.items, leadTime: .sameDay, now: TS.today,
                                        calendar: cal, hour: 18, minute: 45)
        XCTAssertEqual(plan.first?.fireDate, TS.d(2026, 10, 27).addingTimeInterval(18 * 3600 + 45 * 60))
        let readings = [OdometerReadingInfo(date: TS.d(2026, 10, 1), km: 1)]
        XCTAssertFalse(OdometerRules.needsNudge(readings: readings, now: TS.today, calendar: cal, intervalDays: 7))
        XCTAssertTrue(OdometerRules.needsNudge(readings: readings, now: TS.today, calendar: cal, intervalDays: 6))
        XCTAssertFalse(OdometerRules.needsNudge(readings: [], now: TS.today, calendar: cal, intervalDays: 0))
        XCTAssertEqual(OdometerRules.nudgeDates(readings: readings, now: TS.today, calendar: cal, count: 1, hour: 9,
                                                minute: 30, intervalDays: 10),
                       [TS.d(2026, 10, 11).addingTimeInterval(9 * 3600 + 30 * 60)])
        XCTAssertTrue(OdometerRules.nudgeDates(readings: readings, now: TS.today, calendar: cal, intervalDays: 0).isEmpty)
    }
}

final class ExpensesTests: XCTestCase {
    let cal = TS.calendar

    private func snapshot() -> (DataSnapshot, Garage) {
        let g = Garage()
        var snap = g.snapshot
        // 2025-11-03: oil + oil filter + LPG, 3 000 ₴ total, split.
        snap.entries[0].itemCosts = [2_100, 450, 450]
        snap.entries[0].costTotal = 3_000
        // 2026-03-15: cabin filter only, 600 ₴.
        snap.entries[2].costTotal = 600
        // 2026-08-20: brake fluid, $25.
        snap.entries[3].costTotal = 25
        snap.entries[3].currency = .usd
        return (snap, g)
    }

    func testTotalsNeverMixCurrencies() {
        let (snap, _) = snapshot()
        XCTAssertEqual(Expenses.total(snap, currency: .uah), 3_600)
        XCTAssertEqual(Expenses.total(snap, currency: .usd), 25)
        XCTAssertEqual(Expenses.total(snap, currency: .uah, in: Expenses.year(2026, calendar: cal)), 600)
        let byCurrency = Expenses.totalsByCurrency(snap)
        XCTAssertEqual(byCurrency.map(\.0), [.uah, .usd])
    }

    func testByMonthAndCategory() {
        let (snap, _) = snapshot()
        let months = Expenses.byMonth(snap, currency: .uah, year: 2025, calendar: cal)
        XCTAssertEqual(months[10], 3_000)
        XCTAssertEqual(months.reduce(0, +), 3_000)
        // Garage items are custom (no catalog keys): everything is "Other".
        let categories = Expenses.byCategory(snap, currency: .uah)
        XCTAssertEqual(categories.count, 1)
        XCTAssertNil(categories[0].0)
        XCTAssertEqual(categories[0].1, 3_600)
    }

    func testCategoryUsesSplitPricesOrEqualShares() {
        let oil = UUID(), pads = UUID()
        let split = ServiceEntryInfo(date: TS.d(2026, 5, 1), odometerKm: 1, itemIDs: [oil, pads],
                                     itemCatalogKeys: ["engine_oil", "front_pads"], itemCosts: [1_000, 3_000],
                                     costTotal: 4_000)
        let equal = ServiceEntryInfo(date: TS.d(2026, 6, 1), odometerKm: 2, itemIDs: [oil, pads],
                                     itemCatalogKeys: ["engine_oil", "front_pads"], costTotal: 2_000)
        let snap = DataSnapshot(entries: [split, equal])
        let byCat = Dictionary(Expenses.byCategory(snap, currency: .uah).map { ($0.0, $0.1) }, uniquingKeysWith: +)
        XCTAssertEqual(byCat[.engine], 2_000)
        XCTAssertEqual(byCat[.brakes], 4_000)
    }

    func testLastPrice() {
        let (snap, g) = snapshot()
        XCTAssertEqual(Expenses.lastPrice(of: g.engineOil.id, in: snap)?.amount, 2_100)
        XCTAssertEqual(Expenses.lastPrice(of: g.cabin.id, in: snap)?.amount, 600) // single-item entry
        XCTAssertNil(Expenses.lastPrice(of: g.atf.id, in: snap))
    }

    func testMoneyFormat() {
        XCTAssertEqual(TS.plain(AssistantFormat.money(18_450, .uah, .uk)), "18 450 ₴")
        XCTAssertEqual(TS.plain(AssistantFormat.money(1_200.5, .eur, .ru)), "1 200,50 €")
        XCTAssertEqual(AssistantFormat.money(1_200.5, .eur, .en), "€1,200.50")
        XCTAssertEqual(AssistantFormat.money(25, .usd, .en), "$25")
    }

    func testAssistantSpendingAndPrice() {
        let (snap, _) = snapshot()
        let ctx = AssistantContext(snapshot: snap, today: TS.today, calendar: cal, fallbackLanguage: .uk, currency: .uah)
        let year = Assistant.answer("скільки я витратив цього року?", context: ctx)
        XCTAssertEqual(year.lines.map { TS.plain($0.text) }, ["2026 рік:", "Витрачено: 600 ₴ + $25 (записів: 2)"])
        let all = Assistant.answer("сколько я потратил на машину?", context: ctx)
        XCTAssertEqual(TS.plain(all.lines[1].text), "Потрачено: 3 600 ₴ + $25 (записей: 3)")
        let price = Assistant.answer("сколько стоило моторное масло?", context: ctx)
        XCTAssertEqual(price.intent, .price)
        XCTAssertEqual(TS.plain(price.text), "Моторне масло: 2 100 ₴ (3 ноября 2025)")
        XCTAssertEqual(TS.plain(Assistant.answer("how much did the ATF cost?", context: ctx).text),
                       "Масло АКП: no price recorded yet.")
    }
}

final class HistoryImporterTests: XCTestCase {
    let cal = TS.calendar

    func testParsesSloppyLines() {
        let g = Garage()
        let text = """
        12.03.2024 185000 масло моторное, фильтр салона
        05.2023 170 тыс — колодки перед
        окт 2022 158к ГРМ+помпа

        2021 140000 свечи
        15/07/23 160 000 км замена антифриза и термостат
        """
        let rows = HistoryImporter.parse(text, items: g.items, today: TS.today, calendar: cal)
        XCTAssertEqual(rows.count, 5)

        XCTAssertEqual(rows[0].date, TS.d(2024, 3, 12))
        XCTAssertEqual(rows[0].odometerKm, 185_000)
        XCTAssertEqual(rows[0].items, [.existing(g.engineOil.id), .existing(g.cabin.id)])
        XCTAssertFalse(rows[0].needsReview)

        XCTAssertEqual(rows[1].date, TS.d(2023, 5, 1))
        XCTAssertEqual(rows[1].odometerKm, 170_000)
        XCTAssertEqual(rows[1].items, [.catalog("front_pads")])

        XCTAssertEqual(rows[2].date, TS.d(2022, 10, 1))
        XCTAssertEqual(rows[2].odometerKm, 158_000)
        XCTAssertEqual(rows[2].items, [.catalog("timing_belt"), .catalog("water_pump")])

        // Year only: usable but flagged for review.
        XCTAssertEqual(rows[3].date, TS.d(2021, 1, 1))
        XCTAssertTrue(rows[3].needsReview)
        XCTAssertEqual(rows[3].items, [.existing(g.plugs.id)])

        XCTAssertEqual(rows[4].date, TS.d(2023, 7, 15))
        XCTAssertEqual(rows[4].odometerKm, 160_000)
        XCTAssertEqual(rows[4].items, [.catalog("coolant"), .catalog("thermostat")])
    }

    /// A similar-looking word or one shared word is not a match: "радіатор" ≠ "Масло варіатора (CVT)".
    func testStrictMatching() {
        let rows = HistoryImporter.parse("2021 150000 радіатор\n2022 160000 масло варіатора", items: [],
                                         today: TS.today, calendar: cal)
        XCTAssertEqual(rows[0].items, [.custom("Радіатор")])
        XCTAssertTrue(rows[0].needsReview)
        XCTAssertEqual(rows[1].items, [.catalog("cvt_oil")])
        XCTAssertFalse(TextTools.matches(TextTools.tokens("радіатор")[0], TextTools.tokens("варіатора")[0]))
    }

    func testUnknownAndIncompleteLines() {
        let rows = HistoryImporter.parse("чистка инжектора у Васи\n10.10.2030 100000 масло", items: [],
                                         today: TS.today, calendar: cal)
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows[0].needsReview)
        XCTAssertFalse(rows[0].isUsable) // no date, no km
        XCTAssertNil(rows[1].date)       // future date is rejected
        XCTAssertTrue(rows[1].needsReview)
    }
}

final class WearTests: XCTestCase {
    func testWear() {
        let g = Garage()
        let snap = g.snapshot
        let statuses = ForecastEngine.statuses(for: snap, today: TS.today, calendar: TS.calendar)
        // Engine oil: 8 000 of 10 000 km (0.8) but 338.5 of 365 days (0.927): the larger counts.
        let oil = ForecastEngine.wear(item: g.engineOil, forecast: statuses[g.engineOil.id]!.forecast!,
                                      entries: snap.entries, currentOdometerKm: 228_000, today: TS.today)
        XCTAssertEqual(oil!, 338.5 / 365, accuracy: 0.001)
        // Expiry item without records: unknown.
        let ins = ItemInfo(name: "Insurance", kind: .expiry, validUntil: TS.d(2027, 1, 1))
        let f = ForecastEngine.status(for: ins, entries: [], currentOdometerKm: nil, avgKmPerMonth: 0,
                                      today: TS.today, calendar: TS.calendar).forecast!
        XCTAssertNil(ForecastEngine.wear(item: ins, forecast: f, entries: [], currentOdometerKm: nil, today: TS.today))
    }
}
