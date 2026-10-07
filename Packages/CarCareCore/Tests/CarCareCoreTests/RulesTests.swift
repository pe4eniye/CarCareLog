import XCTest
@testable import CarCareCore

final class PartNumberTests: XCTestCase {
    func testNormalize() {
        XCTAssertEqual(PartNumbers.normalize("06l 115-562.a"), "06L115562A")
        XCTAssertEqual(PartNumbers.normalize("  w 719/45 "), "W719/45")
        XCTAssertEqual(PartNumbers.normalize(""), "")
    }

    func testOEMChange() {
        XCTAssertEqual(PartNumbers.oemChange(existing: nil, new: "123"), .none)
        XCTAssertEqual(PartNumbers.oemChange(existing: "06L 115 562", new: "06l-115-562"), .same)
        XCTAssertEqual(PartNumbers.oemChange(existing: "06L 115 562", new: "06L 115 561"),
                       .different(old: "06L 115 562"))
        XCTAssertEqual(PartNumbers.oemChange(existing: "06L 115 562", new: "  "), .none)
    }

    func testConflictsWithOtherItems() {
        let g = Garage()
        // "ATF 1234" equals the ATF analog "ATF-1234" after normalization.
        let c = PartNumbers.conflicts(numbers: ["atf 1234"], editingItemID: g.cabin.id, items: g.items)
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(c.first?.itemName, "Масло АКП")
        XCTAssertEqual(c.first?.asOEM, false)

        let oem = PartNumbers.conflicts(numbers: ["06L115562"], editingItemID: nil, items: g.items)
        XCTAssertEqual(oem.first?.itemID, g.engineOil.id)
        XCTAssertEqual(oem.first?.asOEM, true)

        // The item being edited never conflicts with itself.
        XCTAssertTrue(PartNumbers.conflicts(numbers: ["G055025A2"], editingItemID: g.atf.id, items: g.items).isEmpty)
    }

    func testCleanList() {
        XCTAssertEqual(PartNumbers.cleanList(["A-1", "a 1", " ", "B2"]), ["A-1", "B2"])
    }
}

final class OdometerTests: XCTestCase {
    let cal = TS.calendar
    let readings = [
        OdometerReadingInfo(date: TS.d(2026, 8, 1), km: 225_000),
        OdometerReadingInfo(date: TS.d(2026, 9, 20), km: 228_000)
    ]

    func testCurrentIsLatestByDate() {
        XCTAssertEqual(OdometerRules.current(readings: readings)?.km, 228_000)
        XCTAssertNil(OdometerRules.current(readings: []))
    }

    func testLowerValueWarns() {
        XCTAssertTrue(OdometerRules.isLowerThanCurrent(227_000, readings: readings))
        XCTAssertFalse(OdometerRules.isLowerThanCurrent(228_000, readings: readings))
        XCTAssertFalse(OdometerRules.isLowerThanCurrent(5, readings: []))
    }

    func testServiceEntryAddsReadingOnlyWhenHigher() {
        XCTAssertTrue(OdometerRules.serviceEntryShouldAddReading(entryKm: 229_000, readings: readings))
        XCTAssertFalse(OdometerRules.serviceEntryShouldAddReading(entryKm: 228_000, readings: readings))
        XCTAssertTrue(OdometerRules.serviceEntryShouldAddReading(entryKm: 1, readings: []))
    }

    func testNudgeAfter14Days() {
        // Last reading 20 Sep; 7 Oct is 17 days later.
        XCTAssertTrue(OdometerRules.needsNudge(readings: readings, now: TS.today, calendar: cal))
        XCTAssertFalse(OdometerRules.needsNudge(readings: readings, now: TS.d(2026, 10, 3), calendar: cal))
        XCTAssertTrue(OdometerRules.needsNudge(readings: readings, now: TS.d(2026, 10, 4), calendar: cal))
        XCTAssertTrue(OdometerRules.needsNudge(readings: [], now: TS.today, calendar: cal))
        // A fresh reading resets the counter.
        let fresh = readings + [OdometerReadingInfo(date: TS.d(2026, 10, 7), km: 229_000)]
        XCTAssertFalse(OdometerRules.needsNudge(readings: fresh, now: TS.today, calendar: cal))
    }

    func testNudgeDates() {
        let dates = OdometerRules.nudgeDates(readings: readings, now: TS.today, calendar: cal)
        // 20 Sep + 14 = 4 Oct (past) → 18 Oct, 1 Nov, 15 Nov at 09:00.
        XCTAssertEqual(dates, [TS.d(2026, 10, 18, 9), TS.d(2026, 11, 1, 9), TS.d(2026, 11, 15, 9)])
    }

    func testEntryValidation() {
        XCTAssertEqual(ValidationRules.validateEntry(date: TS.d(2026, 10, 8), odometerKm: 1, itemCount: 1,
                                                     now: TS.today, calendar: cal), [.dateInFuture])
        XCTAssertEqual(ValidationRules.validateEntry(date: TS.d(2026, 10, 7, 23), odometerKm: 1, itemCount: 0,
                                                     now: TS.today, calendar: cal), [.noItems])
        XCTAssertEqual(ValidationRules.validateEntry(date: TS.today, odometerKm: 1, itemCount: 2,
                                                     now: TS.today, calendar: cal), [])
    }

    func testVinWarning() {
        XCTAssertFalse(ValidationRules.vinLooksWrong(nil))
        XCTAssertFalse(ValidationRules.vinLooksWrong(""))
        XCTAssertFalse(ValidationRules.vinLooksWrong("TMBJJ7NE8F0123456"))
        XCTAssertTrue(ValidationRules.vinLooksWrong("TMBJJ7NE8F012345"))
    }
}

final class ReminderPlannerTests: XCTestCase {
    let cal = TS.calendar

    func testGroupsSameDayAndAppliesLeadTime() {
        let g = Garage()
        let statuses = ForecastEngine.statuses(for: g.snapshot, today: TS.today, calendar: cal)
        let plan = ReminderPlanner.plan(statuses: statuses, items: g.items, leadTime: .oneWeek,
                                        now: TS.today, calendar: cal)
        let first = plan[0]
        XCTAssertEqual(first.dueDay, TS.d(2026, 10, 27))
        XCTAssertEqual(first.fireDate, TS.d(2026, 10, 20, 9))
        XCTAssertEqual(first.itemIDs, [g.engineOil.id, g.oilFilter.id, g.lpg.id]) // in list order
        XCTAssertEqual(first.identifier, "due-2026-10-27")
        // ATF and spark plugs share 15 May 2027.
        XCTAssertEqual(plan.first { $0.dueDay == TS.d(2027, 5, 15) }?.itemIDs, [g.atf.id, g.plugs.id])
        XCTAssertEqual(plan.map(\.dueDay), plan.map(\.dueDay).sorted())
    }

    func testPassedLeadTimeFallsBackToDueDay() {
        let g = Garage()
        let statuses = ForecastEngine.statuses(for: g.snapshot, today: TS.today, calendar: cal)
        let plan = ReminderPlanner.plan(statuses: statuses, items: g.items, leadTime: .oneMonth,
                                        now: TS.today, calendar: cal)
        XCTAssertEqual(plan[0].fireDate, TS.d(2026, 10, 27, 9))
    }

    func testSkipsOverdueAndLimitsCount() {
        var items: [ItemInfo] = []
        var entries: [ServiceEntryInfo] = []
        for i in 0..<120 {
            let item = ItemInfo(name: "Item \(i)", intervalMonths: 1)
            items.append(item)
            // One entry per day, so every item gets its own due day; the first ones are overdue.
            entries.append(ServiceEntryInfo(date: cal.date(byAdding: .day, value: i - 40, to: TS.d(2026, 9, 7))!,
                                            odometerKm: 1000, itemIDs: [item.id]))
        }
        let snap = DataSnapshot(car: CarInfo(avgKmPerMonth: 1000), items: items, entries: entries,
                                odometerReadings: [OdometerReadingInfo(date: TS.today, km: 1000)])
        let statuses = ForecastEngine.statuses(for: snap, today: TS.today, calendar: cal)
        let plan = ReminderPlanner.plan(statuses: statuses, items: items, leadTime: .sameDay,
                                        now: TS.today, calendar: cal)
        XCTAssertEqual(plan.count, ReminderPlanner.maxItemReminders)
        XCTAssertTrue(plan.allSatisfy { $0.fireDate > TS.today })
        XCTAssertTrue(plan.allSatisfy { $0.dueDay >= cal.startOfDay(for: TS.today) })
    }
}

final class BackupTests: XCTestCase {
    func testRoundTrip() throws {
        let snap = Garage().snapshot
        let exported = TS.d(2026, 10, 7, 15)
        let data = try BackupCodec.encode(snap, exportedAt: exported)
        let file = try BackupCodec.decode(data)
        XCTAssertEqual(file.formatVersion, BackupFile.currentFormatVersion)
        XCTAssertEqual(file.exportedAt, exported)
        XCTAssertEqual(file.snapshot, snap)

        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"formatVersion\" : 1"))
        XCTAssertTrue(json.contains("Моторне масло"))
    }

    func testFractionalSecondsSurvive() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000.25)
        let snap = DataSnapshot(odometerReadings: [OdometerReadingInfo(date: date, km: 1)])
        let back = try BackupCodec.decode(BackupCodec.encode(snap, exportedAt: date))
        XCTAssertEqual(back.odometerReadings.first!.date.timeIntervalSince1970, 1_790_000_000.25, accuracy: 0.001)
    }

    func testRejectsForeignFile() {
        XCTAssertThrowsError(try BackupCodec.decode(Data("{\"hello\":1}".utf8))) {
            XCTAssertEqual($0 as? BackupError, .notABackup)
        }
        XCTAssertThrowsError(try BackupCodec.decode(Data("not json".utf8))) {
            XCTAssertEqual($0 as? BackupError, .notABackup)
        }
    }

    func testRejectsNewerVersion() {
        let json = "{\"app\":\"CarCareLog\",\"formatVersion\":99}"
        XCTAssertThrowsError(try BackupCodec.decode(Data(json.utf8))) {
            XCTAssertEqual($0 as? BackupError, .newerFormat(99))
        }
    }

    func testRejectsBrokenReferences() throws {
        var snap = Garage().snapshot
        snap.items.removeFirst()
        let data = try BackupCodec.encode(snap, exportedAt: TS.today)
        XCTAssertThrowsError(try BackupCodec.decode(data)) {
            XCTAssertEqual($0 as? BackupError, .brokenReferences)
        }
    }

    func testFileName() {
        XCTAssertEqual(BackupCodec.suggestedFileName(date: TS.today, calendar: TS.calendar),
                       "CarCareLog-backup-2026-10-07.json")
    }
}
