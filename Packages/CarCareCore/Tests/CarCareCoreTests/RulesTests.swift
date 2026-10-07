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

    func testServiceEntriesCountAsOdometerPoints() {
        // An entry recorded today with a higher km becomes the current odometer...
        let today = ServiceEntryInfo(date: TS.d(2026, 10, 7), odometerKm: 229_000, itemIDs: [UUID()])
        XCTAssertEqual(OdometerRules.current(readings: readings, entries: [today], calendar: cal)?.km, 229_000)
        // ...and deleting it (passing no entries) brings the previous value back. Nothing was copied.
        XCTAssertEqual(OdometerRules.current(readings: readings, entries: [], calendar: cal)?.km, 228_000)

        // A replacement logged late for an earlier date does not roll the current odometer back.
        let backdated = ServiceEntryInfo(date: TS.d(2026, 7, 1), odometerKm: 220_000, itemIDs: [UUID()])
        XCTAssertEqual(OdometerRules.current(readings: readings, entries: [backdated], calendar: cal)?.km, 228_000)

        // Same day: the highest km wins, whatever the time of day.
        let morning = OdometerReadingInfo(date: TS.d(2026, 10, 7, 9), km: 228_500)
        let entryMidnight = ServiceEntryInfo(date: TS.d(2026, 10, 7), odometerKm: 229_100, itemIDs: [UUID()])
        XCTAssertEqual(OdometerRules.current(readings: readings + [morning], entries: [entryMidnight],
                                             calendar: cal)?.km, 229_100)

        // Rolling the odometer back with a newer reading: the newest wins (the UI warns before saving).
        let rollback = OdometerReadingInfo(date: TS.d(2026, 10, 8), km: 225_000)
        XCTAssertEqual(OdometerRules.current(readings: readings + [rollback], entries: [today], calendar: cal)?.km,
                       225_000)
    }

    func testServiceEntryTodayResetsNudge() {
        let entry = ServiceEntryInfo(date: TS.d(2026, 10, 7), odometerKm: 228_000, itemIDs: [UUID()])
        XCTAssertTrue(OdometerRules.needsNudge(readings: readings, now: TS.today, calendar: cal))
        XCTAssertFalse(OdometerRules.needsNudge(readings: readings, entries: [entry], now: TS.today, calendar: cal))
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
        // 20 Sep + 14 = 4 Oct (past) → 18 Oct, 1 Nov, 15 Nov at 11:00.
        XCTAssertEqual(dates, [TS.d(2026, 10, 18, 11), TS.d(2026, 11, 1, 11), TS.d(2026, 11, 15, 11)])
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

    func testAdvanceAndDueDayRemindersAt11() {
        let g = Garage()
        let statuses = ForecastEngine.statuses(for: g.snapshot, today: TS.today, calendar: cal)
        let plan = ReminderPlanner.plan(statuses: statuses, items: g.items, leadTime: .oneWeek,
                                        now: TS.today, calendar: cal)
        // A week before 27 Oct, then on 27 Oct itself, both at 11:00.
        XCTAssertEqual(plan[0].identifier, "due-2026-10-27-advance")
        XCTAssertTrue(plan[0].isAdvance)
        XCTAssertEqual(plan[0].fireDate, TS.d(2026, 10, 20, 11))
        XCTAssertEqual(plan[0].itemIDs, [g.engineOil.id, g.oilFilter.id, g.lpg.id]) // in list order
        XCTAssertEqual(plan[1].identifier, "due-2026-10-27")
        XCTAssertFalse(plan[1].isAdvance)
        XCTAssertEqual(plan[1].fireDate, TS.d(2026, 10, 27, 11))
        // ATF and spark plugs share 15 May 2027.
        XCTAssertEqual(plan.first { $0.dueDay == TS.d(2027, 5, 15) }?.itemIDs, [g.atf.id, g.plugs.id])
        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted())
    }

    func testPassedLeadTimeKeepsOnlyDueDay() {
        let g = Garage()
        let statuses = ForecastEngine.statuses(for: g.snapshot, today: TS.today, calendar: cal)
        let plan = ReminderPlanner.plan(statuses: statuses, items: g.items, leadTime: .oneMonth,
                                        now: TS.today, calendar: cal)
        XCTAssertEqual(plan[0].fireDate, TS.d(2026, 10, 27, 11))
        XCTAssertFalse(plan[0].isAdvance)
        XCTAssertNil(plan.first { $0.identifier == "due-2026-10-27-advance" })
    }

    func testArchivedItemsGetNoReminders() {
        let g = Garage()
        var snap = g.snapshot
        for i in snap.items.indices where snap.items[i].id == g.lpg.id { snap.items[i].isArchived = true }
        let statuses = ForecastEngine.statuses(for: snap, today: TS.today, calendar: cal)
        XCTAssertNil(statuses[g.lpg.id])
        let plan = ReminderPlanner.plan(statuses: statuses, items: snap.items, leadTime: .sameDay,
                                        now: TS.today, calendar: cal)
        XCTAssertFalse(plan.contains { $0.itemIDs.contains(g.lpg.id) })
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
        let plan = ReminderPlanner.plan(statuses: statuses, items: items, leadTime: .oneWeek,
                                        now: TS.today, calendar: cal)
        XCTAssertEqual(plan.count, ReminderPlanner.maxReminders)
        XCTAssertTrue(plan.allSatisfy { $0.fireDate > TS.today })
        XCTAssertTrue(plan.allSatisfy { $0.dueDay >= cal.startOfDay(for: TS.today) })
        XCTAssertEqual(Set(plan.map(\.identifier)).count, plan.count)
    }
}

final class BackupTests: XCTestCase {
    func testRoundTrip() throws {
        var snap = Garage().snapshot
        snap.items[0].isArchived = true
        snap.entries[0].itemNames = ["Масло (старе)", "Фільтр", "ГБО"]
        snap.car?.vin = "TMBJJ7NE8F0123456"
        let exported = TS.d(2026, 10, 7, 15)
        let data = try BackupCodec.encode(snap, exportedAt: exported)
        let file = try BackupCodec.decode(data)
        XCTAssertEqual(file.formatVersion, BackupFile.currentFormatVersion)
        XCTAssertEqual(file.exportedAt, exported)
        XCTAssertEqual(file.snapshot, snap)

        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"formatVersion\" : 2"))
        XCTAssertTrue(json.contains("Моторне масло"))
    }

    func testReadsFormatVersion1() throws {
        let item = UUID(), entry = UUID(), car = UUID()
        let json = """
        {"app":"CarCareLog","formatVersion":1,"exportedAt":"2026-10-07T12:00:00Z",
         "car":{"id":"\(car)","make":"Skoda","model":"Octavia","year":2015,"avgKmPerMonth":1500},
         "items":[{"id":"\(item)","name":"Масло","aliases":[],"analogNumbers":[],"intervalKm":10000}],
         "entries":[{"id":"\(entry)","date":"2026-01-10T00:00:00Z","odometerKm":200000,"itemIDs":["\(item)"]}],
         "odometerReadings":[]}
        """
        let file = try BackupCodec.decode(Data(json.utf8))
        XCTAssertEqual(file.car?.name, "Skoda Octavia")
        XCTAssertEqual(file.items.first?.isArchived, false)
        XCTAssertEqual(file.entries.first?.itemNames, [])
        XCTAssertEqual(file.entries.first?.displayNames(items: file.items), ["Масло"])
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

    func testEntriesOfDeletedItemsKeepTheirNames() throws {
        var snap = Garage().snapshot
        snap.entries[1].itemNames = ["Масло АКП", "Свічки запалювання"]
        let atfID = snap.entries[1].itemIDs[0]
        snap.items.removeAll { $0.id == atfID }
        let file = try BackupCodec.decode(BackupCodec.encode(snap, exportedAt: TS.today))
        XCTAssertEqual(file.entries[1].displayNames(items: file.items), ["Масло АКП", "Свічки запалювання"])
    }

    func testFileName() {
        XCTAssertEqual(BackupCodec.suggestedFileName(date: TS.today, calendar: TS.calendar),
                       "CarCareLog-backup-2026-10-07.json")
    }
}
