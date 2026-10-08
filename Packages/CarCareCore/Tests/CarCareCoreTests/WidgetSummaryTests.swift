import XCTest
@testable import CarCareCore

final class WidgetSummaryTests: XCTestCase {
    func testNearestDayAndOverdue() {
        let g = Garage()
        let r = WidgetSummary.make(snapshot: g.snapshot, today: TS.today, calendar: TS.calendar)
        XCTAssertEqual(r.dueDay, TS.d(2026, 10, 1)) // the October card
        XCTAssertEqual(r.itemNames, ["Моторне масло", "Масляний фільтр", "Фільтри ГБО"])
        XCTAssertEqual(r.overdueNames, [])

        var snap = g.snapshot
        snap.odometerReadings.append(OdometerReadingInfo(date: TS.d(2026, 10, 6), km: 231_000))
        let overdue = WidgetSummary.make(snapshot: snap, today: TS.today, calendar: TS.calendar)
        XCTAssertEqual(overdue.overdueNames, ["Моторне масло", "Масляний фільтр", "Фільтри ГБО"])
        XCTAssertEqual(overdue.dueDay, TS.d(2026, 12, 1)) // cabin filter: 239 000 km, 80 days at 100 km/day → December
    }

    func testEmpty() {
        let r = WidgetSummary.make(snapshot: DataSnapshot(), today: TS.today, calendar: TS.calendar)
        XCTAssertNil(r.dueDay)
        XCTAssertTrue(r.itemNames.isEmpty)
    }

    func testCodable() throws {
        let s = WidgetSnapshot(generatedAt: TS.today, dueDay: TS.d(2026, 11, 20), dueDayText: "20 листопада",
                               itemsText: "Масло + фільтр", overdueText: "", emptyText: "—")
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(WidgetSnapshot.self, from: data), s)
    }
}
