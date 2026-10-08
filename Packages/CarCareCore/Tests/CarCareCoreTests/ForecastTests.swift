import XCTest
@testable import CarCareCore

final class ForecastTests: XCTestCase {
    let cal = TS.calendar
    let today = TS.today

    private func forecast(_ item: ItemInfo, entries: [ServiceEntryInfo], current: Int?, avg: Double = 3040,
                          file: StaticString = #filePath, line: UInt = #line) -> ItemForecast {
        let status = ForecastEngine.status(for: item, entries: entries, currentOdometerKm: current,
                                           avgKmPerMonth: avg, today: today, calendar: cal)
        guard let f = status.forecast else {
            XCTFail("Expected a forecast, got \(status)", file: file, line: line)
            fatalError()
        }
        return f
    }

    func testTimeOnly() {
        let item = ItemInfo(name: "Brake fluid", intervalMonths: 6)
        let entry = ServiceEntryInfo(date: TS.d(2026, 6, 1), odometerKm: 200_000, itemIDs: [item.id])
        let f = forecast(item, entries: [entry], current: 210_000)
        XCTAssertEqual(f.dueDate, TS.d(2026, 12, 1))
        XCTAssertEqual(f.reason, .time)
        XCTAssertNil(f.dueKm)
        XCTAssertFalse(f.isOverdue)
        // 55 days from 7 Oct to 1 Dec at 100 km/day.
        XCTAssertEqual(f.predictedOdometerKm, 215_500)
    }

    func testTimeOnlyOverdue() {
        let item = ItemInfo(name: "Brake fluid", intervalMonths: 6)
        let entry = ServiceEntryInfo(date: TS.d(2026, 1, 15), odometerKm: 200_000, itemIDs: [item.id])
        let f = forecast(item, entries: [entry], current: 210_000)
        XCTAssertEqual(f.dueDate, TS.d(2026, 7, 15))
        XCTAssertTrue(f.isOverdue)
        XCTAssertEqual(f.predictedOdometerKm, 210_000)
    }

    func testKmOnly() {
        let item = ItemInfo(name: "Oil", intervalKm: 10_000)
        let entry = ServiceEntryInfo(date: TS.d(2026, 5, 1), odometerKm: 220_000, itemIDs: [item.id])
        let f = forecast(item, entries: [entry], current: 225_000)
        XCTAssertEqual(f.dueKm, 230_000)
        XCTAssertEqual(f.reason, .mileage)
        XCTAssertEqual(f.dueDate, TS.d(2026, 11, 26)) // 5000 km / 100 km per day = 50 days
        XCTAssertEqual(f.predictedOdometerKm, 230_000)
        XCTAssertFalse(f.isOverdue)
    }

    func testBothMileageFirst() {
        let item = ItemInfo(name: "Oil", intervalKm: 10_000, intervalMonths: 12)
        let entry = ServiceEntryInfo(date: TS.d(2025, 11, 3), odometerKm: 220_000, itemIDs: [item.id])
        let f = forecast(item, entries: [entry], current: 228_000)
        XCTAssertEqual(f.dueByTime, TS.d(2026, 11, 3))
        XCTAssertEqual(f.dueByMileage, TS.d(2026, 10, 27))
        XCTAssertEqual(f.dueDate, TS.d(2026, 10, 27))
        XCTAssertEqual(f.reason, .mileage)
    }

    func testBothTimeFirst() {
        let item = ItemInfo(name: "Oil", intervalKm: 10_000, intervalMonths: 12)
        let entry = ServiceEntryInfo(date: TS.d(2025, 11, 3), odometerKm: 220_000, itemIDs: [item.id])
        let f = forecast(item, entries: [entry], current: 221_000)
        XCTAssertEqual(f.dueDate, TS.d(2026, 11, 3))
        XCTAssertEqual(f.reason, .time)
        XCTAssertEqual(f.dueKm, 230_000)
        XCTAssertEqual(f.predictedOdometerKm, 223_700) // 27 days × 100 km
    }

    func testOverdueByKm() {
        let item = ItemInfo(name: "Oil", intervalKm: 10_000, intervalMonths: 12)
        let entry = ServiceEntryInfo(date: TS.d(2026, 5, 1), odometerKm: 220_000, itemIDs: [item.id])
        let f = forecast(item, entries: [entry], current: 231_000)
        XCTAssertTrue(f.isOverdue)
        XCTAssertTrue(f.overdueByKm)
        XCTAssertFalse(f.overdueByTime)
        XCTAssertNil(f.overdueLimits.date)
        XCTAssertEqual(f.overdueLimits.km, 230_000)
        XCTAssertEqual(f.dueByMileage, cal.startOfDay(for: today))
        XCTAssertEqual(f.reason, .mileage)
        XCTAssertEqual(f.predictedOdometerKm, 231_000)
    }

    func testExactlyAtDueKmIsOverdue() {
        let item = ItemInfo(name: "Oil", intervalKm: 10_000)
        let entry = ServiceEntryInfo(date: TS.d(2026, 5, 1), odometerKm: 220_000, itemIDs: [item.id])
        XCTAssertTrue(forecast(item, entries: [entry], current: 230_000).isOverdue)
    }

    func testNoHistoryAndNoInterval() {
        let withInterval = ItemInfo(name: "Air filter", intervalKm: 30_000)
        let noInterval = ItemInfo(name: "Wipers")
        XCTAssertEqual(ForecastEngine.status(for: withInterval, entries: [], currentOdometerKm: 100,
                                             avgKmPerMonth: 1000, today: today, calendar: cal), .noHistory)
        let entry = ServiceEntryInfo(date: TS.d(2026, 1, 1), odometerKm: 1, itemIDs: [noInterval.id])
        XCTAssertEqual(ForecastEngine.status(for: noInterval, entries: [entry], currentOdometerKm: 100,
                                             avgKmPerMonth: 1000, today: today, calendar: cal), .noInterval)
    }

    func testAvgZeroKmOnlyHasNoDate() {
        let item = ItemInfo(name: "Oil", intervalKm: 10_000)
        let entry = ServiceEntryInfo(date: TS.d(2026, 5, 1), odometerKm: 220_000, itemIDs: [item.id])
        for avg in [0.0, -500.0] {
            let f = forecast(item, entries: [entry], current: 225_000, avg: avg)
            XCTAssertNil(f.dueDate)
            XCTAssertNil(f.dueByMileage)
            XCTAssertFalse(f.isOverdue)
            XCTAssertEqual(f.dueKm, 230_000)
        }
    }

    func testAvgZeroStillDetectsOverdueAndUsesTime() {
        let kmOnly = ItemInfo(name: "Oil", intervalKm: 10_000)
        let e1 = ServiceEntryInfo(date: TS.d(2026, 5, 1), odometerKm: 220_000, itemIDs: [kmOnly.id])
        let overdue = forecast(kmOnly, entries: [e1], current: 235_000, avg: 0)
        XCTAssertTrue(overdue.isOverdue)
        XCTAssertEqual(overdue.dueDate, cal.startOfDay(for: today))

        let both = ItemInfo(name: "Cabin", intervalKm: 15_000, intervalMonths: 12)
        let e2 = ServiceEntryInfo(date: TS.d(2026, 3, 15), odometerKm: 220_000, itemIDs: [both.id])
        let f = forecast(both, entries: [e2], current: 225_000, avg: 0)
        XCTAssertEqual(f.dueDate, TS.d(2027, 3, 15))
        XCTAssertEqual(f.reason, .time)
        XCTAssertEqual(f.predictedOdometerKm, 225_000)
    }

    func testUsesLatestEntry() {
        let item = ItemInfo(name: "Oil", intervalKm: 10_000)
        let old = ServiceEntryInfo(date: TS.d(2025, 1, 1), odometerKm: 200_000, itemIDs: [item.id])
        let new = ServiceEntryInfo(date: TS.d(2026, 5, 1), odometerKm: 220_000, itemIDs: [item.id])
        let other = ServiceEntryInfo(date: TS.d(2026, 9, 1), odometerKm: 226_000, itemIDs: [UUID()])
        let f = forecast(item, entries: [new, other, old], current: 225_000)
        XCTAssertEqual(f.lastOdometerKm, 220_000)
        XCTAssertEqual(f.lastDate, TS.d(2026, 5, 1))
    }

    func testNoCurrentOdometerUsesLastEntry() {
        let item = ItemInfo(name: "Oil", intervalKm: 10_000)
        let entry = ServiceEntryInfo(date: TS.d(2026, 5, 1), odometerKm: 220_000, itemIDs: [item.id])
        let f = forecast(item, entries: [entry], current: nil)
        XCTAssertEqual(f.dueDate, TS.d(2027, 1, 15)) // 10 000 km / 100 = 100 days
    }

    func testGroups() {
        let g = Garage()
        let statuses = ForecastEngine.statuses(for: g.snapshot, today: today, calendar: cal)
        let groups = ForecastGroups.make(from: statuses, calendar: cal)
        XCTAssertTrue(groups.overdue.isEmpty)
        // Engine oil, oil filter and LPG filters are all due on 27 Oct (230 000 km): the October card.
        XCTAssertEqual(groups.upcoming.first?.month, TS.d(2026, 10, 1))
        XCTAssertEqual(Set(groups.upcoming.first?.forecasts.map(\.itemID) ?? []),
                       Set([g.engineOil.id, g.oilFilter.id, g.lpg.id]))
        let days = groups.upcoming.map(\.day)
        XCTAssertEqual(days, days.sorted())
        XCTAssertNil(statuses[g.airFilter.id]?.forecast)
    }
}
