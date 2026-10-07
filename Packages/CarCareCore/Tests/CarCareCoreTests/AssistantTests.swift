import XCTest
@testable import CarCareCore

final class AssistantTests: XCTestCase {
    let g = Garage()

    private func ask(_ q: String, fallback: AssistantLanguage = .uk) -> AssistantReply {
        Assistant.answer(q, context: g.context(fallback: fallback))
    }

    private func parse(_ q: String) -> ParsedQuery {
        QueryParser.parse(q, items: g.items, today: TS.today, calendar: TS.calendar, fallbackLanguage: .uk)
    }

    // MARK: Fixtures from the spec (Russian)

    func testLastDoneEngineOilRu() {
        let r = ask("когда я последний раз менял моторное масло?")
        XCTAssertEqual(r.language, .ru)
        XCTAssertEqual(r.intent, .lastDone)
        XCTAssertEqual(r.kind, .answer)
        XCTAssertEqual(TS.plain(r.text), "Моторне масло: 220 000 км (3 ноября 2025)")
    }

    func testLastDoneSparkPlugsRu() {
        let r = ask("напомни когда я менял свечи зажигания?")
        XCTAssertEqual(r.intent, .lastDone)
        XCTAssertEqual(TS.plain(r.text), "Свічки запалювання: 190 000 км (10 июня 2024)")
    }

    func testNextDueAtfRu() {
        let r = ask("когда нужно поменять масло АКП?")
        XCTAssertEqual(r.intent, .nextDue)
        XCTAssertEqual(TS.plain(r.text), "Масло АКП: 15 мая 2027 (250 000 км) — по пробегу")
    }

    func testPartNumberAtfRu() {
        let r = ask("дай номер масла АКП")
        XCTAssertEqual(r.intent, .partNumber)
        XCTAssertEqual(r.lines.map(\.text), ["Масло АКП", "OEM: G 055 025 A2", "Аналоги: ATF-1234, Mobil ATF 3309"])
        XCTAssertEqual(r.lines[1].copyValues, ["G 055 025 A2"])
        XCTAssertEqual(r.lines[2].copyValues, ["ATF-1234", "Mobil ATF 3309"])
    }

    func testCabinFilterNextDueRu() {
        for q in ["когда пора менять салонный фильтр?", "через сколько надо поменять фильтр салона?"] {
            let r = ask(q)
            XCTAssertEqual(r.intent, .nextDue, q)
            XCTAssertEqual(TS.plain(r.text), "Фільтр салону: 25 января 2027 (239 000 км) — по пробегу", q)
        }
    }

    func testDueAtMileageRu() {
        for q in ["напиши список всего что нужно поменять на пробеге 250тыс", "что нужно заменить на 250?"] {
            let r = ask(q)
            XCTAssertEqual(r.intent, .dueAtMileage(250_000), q)
            let lines = r.lines.map { TS.plain($0.text) }
            XCTAssertEqual(lines.first, "До 250 000 км нужно заменить:", q)
            let body = lines.joined(separator: "\n")
            for name in ["Моторне масло", "Масляний фільтр", "Фільтри ГБО", "Фільтр салону", "Масло АКП",
                         "Свічки запалювання"] {
                XCTAssertTrue(body.contains("• \(name) — "), "\(q): missing \(name)")
            }
            XCTAssertFalse(body.contains("• Гальмівна рідина"), q) // due in 2028, far beyond 250 000
            XCTAssertEqual(lines.last, "Без записей, не учтено: Повітряний фільтр", q)
        }
    }

    func testHistoryThisYearRu() {
        let r = ask("что я менял в этом году?")
        guard case .historyForPeriod(let p)? = r.intent else { return XCTFail("intent \(String(describing: r.intent))") }
        XCTAssertEqual(p.kind, .thisYear)
        XCTAssertEqual(r.lines.map { TS.plain($0.text) }, [
            "2026 год:",
            "20 августа 2026 · 227 000 км — Гальмівна рідина",
            "15 марта 2026 · 224 000 км — Фільтр салону"
        ])
    }

    func testLpgFiltersRu() {
        let next = ask("когда пора менять фильтры ГБО?")
        XCTAssertEqual(next.intent, .nextDue)
        XCTAssertEqual(TS.plain(next.text), "Фільтри ГБО: 27 октября 2026 (230 000 км) — по пробегу")
        for q in ["когда менялся фильтр ГБО?", "когда ГБО фильтры менялись последний раз?"] {
            let r = ask(q)
            XCTAssertEqual(r.intent, .lastDone, q)
            XCTAssertEqual(TS.plain(r.text), "Фільтри ГБО: 220 000 км (3 ноября 2025)", q)
        }
    }

    // MARK: Ukrainian

    func testUkrainianVariants() {
        let last = ask("коли я востаннє міняв моторну оливу?")
        XCTAssertEqual(last.language, .uk)
        XCTAssertEqual(last.intent, .lastDone)
        XCTAssertEqual(TS.plain(last.text), "Моторне масло: 220 000 км (3 листопада 2025)")

        let cabin = ask("коли треба міняти фільтр салону?")
        XCTAssertEqual(cabin.intent, .nextDue)
        XCTAssertEqual(TS.plain(cabin.text), "Фільтр салону: 25 січня 2027 (239 000 км) — за пробігом")

        let number = ask("мені потрібен номер оливи АКПП")
        XCTAssertEqual(number.language, .uk)
        XCTAssertEqual(number.intent, .partNumber)
        XCTAssertEqual(number.lines.last?.text, "Аналоги: ATF-1234, Mobil ATF 3309")

        let mileage = ask("що замінити на 250 тис?")
        XCTAssertEqual(mileage.intent, .dueAtMileage(250_000))
        XCTAssertEqual(TS.plain(mileage.lines[0].text), "До 250 000 км потрібно замінити:")

        let history = ask("що я міняв цього року?")
        XCTAssertEqual(history.language, .uk)
        XCTAssertEqual(TS.plain(history.lines[0].text), "2026 рік:")
        XCTAssertEqual(history.lines.count, 3)

        let plugs = ask("коли міняв свічки?")
        XCTAssertEqual(plugs.intent, .lastDone)
        XCTAssertEqual(TS.plain(plugs.text), "Свічки запалювання: 190 000 км (10 червня 2024)")

        let lpg = ask("коли мінялися фільтри ГБО?")
        XCTAssertEqual(TS.plain(lpg.text), "Фільтри ГБО: 220 000 км (3 листопада 2025)")
    }

    // MARK: English and mixed

    func testEnglishVariants() {
        let last = ask("When did I last change the engine oil?")
        XCTAssertEqual(last.language, .en)
        XCTAssertEqual(last.intent, .lastDone)
        XCTAssertEqual(TS.plain(last.text), "Моторне масло: 220,000 km (3 November 2025)")

        let cabin = ask("When is the cabin filter due?")
        XCTAssertEqual(cabin.intent, .nextDue)
        XCTAssertEqual(TS.plain(cabin.text), "Фільтр салону: 25 January 2027 (239,000 km) — by mileage")

        let atf = ask("ATF part number")
        XCTAssertEqual(atf.intent, .partNumber)
        XCTAssertEqual(atf.lines.first?.text, "Масло АКП")
        XCTAssertEqual(atf.lines.last?.text, "Analogs: ATF-1234, Mobil ATF 3309")

        XCTAssertEqual(ask("What is due at 250k?").intent, .dueAtMileage(250_000))
        XCTAssertEqual(ask("what needs replacing at 250000 km").intent, .dueAtMileage(250_000))

        let history = ask("What did I change this year?")
        XCTAssertEqual(TS.plain(history.lines[0].text), "2026:")

        let plugs = ask("when did i change spark plugs")
        XCTAssertEqual(TS.plain(plugs.text), "Свічки запалювання: 190,000 km (10 June 2024)")
    }

    func testMixedLanguage() {
        let r = ask("когда менял ATF?")
        XCTAssertEqual(r.language, .ru)
        XCTAssertEqual(r.intent, .lastDone)
        XCTAssertEqual(TS.plain(r.text), "Масло АКП: 190 000 км (10 июня 2024)")
    }

    // MARK: Typos, choices, unknowns

    func testTypos() {
        XCTAssertEqual(parse("когда менял маторное масло").itemIDs, [g.engineOil.id])
        XCTAssertEqual(parse("когда менять фильр салона").itemIDs, [g.cabin.id])
        XCTAssertEqual(parse("коли міняв свічкі запалювання").itemIDs, [g.plugs.id])
    }

    func testSeveralMatchesOfferChoices() {
        var snap = g.snapshot
        let liquid = ItemInfo(name: "Фильтр ГБО жидкой фазы", intervalKm: 10_000)
        let gas = ItemInfo(name: "Фильтр ГБО газовой фазы", intervalKm: 20_000)
        snap.items.removeAll { $0.id == g.lpg.id }
        snap.items += [liquid, gas]
        let ctx = AssistantContext(snapshot: snap, today: TS.today, calendar: TS.calendar, fallbackLanguage: .uk)
        let r = Assistant.answer("когда пора менять фильтры ГБО?", context: ctx)
        XCTAssertEqual(r.kind, .chooseItem)
        XCTAssertEqual(Set(r.choices.map(\.id)), Set([liquid.id, gas.id]))
        XCTAssertEqual(r.text, "Нашёл несколько позиций — выберите:")

        let chosen = Assistant.answer("когда пора менять фильтры ГБО?", context: ctx, chosenItemID: gas.id)
        XCTAssertEqual(chosen.kind, .answer)
        XCTAssertTrue(chosen.text.hasPrefix("Фильтр ГБО газовой фазы: "))
    }

    func testNotUnderstood() {
        let r = ask("привет как дела")
        XCTAssertEqual(r.kind, .notUnderstood)
        XCTAssertNil(r.intent)
        XCTAssertFalse(r.examples.isEmpty)
        XCTAssertEqual(r.language, .ru)
    }

    func testItemNotFoundNeverInventsData() {
        let r = ask("когда менять ремень ГРМ?")
        XCTAssertEqual(r.kind, .itemNotFound)
        XCTAssertTrue(r.choices.isEmpty)
        XCTAssertFalse(r.examples.isEmpty)
    }

    func testNoRecordsAndNoInterval() {
        XCTAssertEqual(TS.plain(ask("когда менял воздушный фильтр?").text), "Повітряний фільтр: записей пока нет.")
        XCTAssertEqual(TS.plain(ask("когда менять воздушный фильтр?").text),
                       "Повітряний фільтр: записей пока нет, прогноз невозможен.")
        XCTAssertEqual(TS.plain(ask("номер воздушного фильтра").text), "Повітряний фільтр: номер не указан.")
    }

    func testOverdueText() {
        var snap = g.snapshot
        snap.odometerReadings.append(OdometerReadingInfo(date: TS.d(2026, 10, 6), km: 231_000))
        let ctx = AssistantContext(snapshot: snap, today: TS.today, calendar: TS.calendar, fallbackLanguage: .uk)
        let r = Assistant.answer("коли міняти моторне масло?", context: ctx)
        // Only the exceeded limit is named: km, not "today".
        XCTAssertEqual(TS.plain(r.text), "Моторне масло: прострочено (230 000 км)")

        // Both limits exceeded: date and km.
        var late = g.snapshot
        late.odometerReadings.append(OdometerReadingInfo(date: TS.d(2026, 12, 1), km: 231_000))
        let lateCtx = AssistantContext(snapshot: late, today: TS.d(2026, 12, 1), calendar: TS.calendar,
                                       fallbackLanguage: .uk)
        XCTAssertEqual(TS.plain(Assistant.answer("коли міняти моторне масло?", context: lateCtx).text),
                       "Моторне масло: прострочено (3 листопада 2026, 230 000 км)")
    }

    // MARK: Parsing helpers

    func testMileageExtraction() {
        XCTAssertEqual(QueryParser.extractMileage("на пробеге 250тыс"), 250_000)
        XCTAssertEqual(QueryParser.extractMileage("на 250 тис."), 250_000)
        XCTAssertEqual(QueryParser.extractMileage("at 250k"), 250_000)
        XCTAssertEqual(QueryParser.extractMileage("до 250000"), 250_000)
        XCTAssertEqual(QueryParser.extractMileage("до 250 000 км"), 250_000)
        XCTAssertEqual(QueryParser.extractMileage("на 250"), 250_000)
        XCTAssertEqual(QueryParser.extractMileage("на 245500"), 245_500)
        XCTAssertNil(QueryParser.extractMileage("номер масла 5w30"))
        XCTAssertNil(QueryParser.extractMileage("что я менял в 2025 году"))
        XCTAssertNil(QueryParser.extractMileage("когда менять масло"))
    }

    func testPeriods() {
        let cal = TS.calendar
        let thisYear = QueryParser.extractPeriod("цього року", today: TS.today, calendar: cal)
        XCTAssertEqual(thisYear?.start, TS.d(2026, 1, 1))
        XCTAssertEqual(thisYear?.end, TS.d(2027, 1, 1))
        XCTAssertEqual(QueryParser.extractPeriod("в прошлом году", today: TS.today, calendar: cal)?.kind, .lastYear)
        XCTAssertEqual(QueryParser.extractPeriod("this month", today: TS.today, calendar: cal)?.start, TS.d(2026, 10, 1))
        XCTAssertEqual(QueryParser.extractPeriod("в 2025 году", today: TS.today, calendar: cal)?.kind, .year(2025))
        XCTAssertNil(QueryParser.extractPeriod("когда менять масло", today: TS.today, calendar: cal))
    }

    func testHistoryForExplicitYear() {
        let r = ask("что я менял в 2025 году?")
        XCTAssertEqual(r.lines.map { TS.plain($0.text) }, [
            "2025 год:",
            "3 ноября 2025 · 220 000 км — Моторне масло, Масляний фільтр, Фільтри ГБО"
        ])
    }

    func testNormalization() {
        XCTAssertEqual(TextTools.normalize("Ёлки-палки, ЗАМЕНА масла!"), "елки палки замена масла")
        XCTAssertEqual(TextTools.normalize("п'ять"), "пять")
        XCTAssertEqual(TextTools.editDistance("фильтр", "фильр"), 1)
    }
}
