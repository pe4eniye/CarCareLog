import XCTest

/// End-to-end checks of real taps in the simulator, in demo mode (sample data in memory, English UI).
final class CarCareLogUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Settings first (UserDefaults argument domain), demo flags last.
        app.launchArguments = ["-settings.language", "en", "-settings.theme", "light", "-demo", "-startTab", "home"]
        app.launch()
        XCTAssertTrue(app.buttons["home.update"].waitForExistence(timeout: 15))
    }

    private func openLogService() {
        // Toolbar buttons can't be "scrolled to visible" by XCUITest on iOS 18, so tap by coordinate.
        let plus = app.buttons["addMenu"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        plus.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let item = app.buttons["Log service"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        XCTAssertTrue(app.buttons["entry.pick"].waitForExistence(timeout: 5))
    }

    /// Picking and unpicking items, with and without search; "Done · N selected" appears only when N ≥ 1,
    /// also while the search field is active.
    func testPickerSelectDeselectAndSearch() {
        openLogService()
        app.buttons["entry.pick"].tap()

        let oil = app.buttons["check.Engine oil"]
        XCTAssertTrue(oil.waitForExistence(timeout: 5))
        oil.tap()
        let done = app.buttons["picker.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        XCTAssertEqual(done.label, "Done · 1 selected")

        // Unpick: the bar disappears.
        oil.tap()
        XCTAssertFalse(done.waitForExistence(timeout: 1))

        // Search, pick: the search closes and the bar is there.
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("brake")
        let fluid = app.buttons["check.Brake fluid"]
        XCTAssertTrue(fluid.waitForExistence(timeout: 5))
        fluid.tap()
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        XCTAssertEqual(done.label, "Done · 1 selected")

        // The search closed by itself after the pick, the selection is kept.
        XCTAssertTrue(app.buttons["check.Engine oil"].waitForExistence(timeout: 3))
        done.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(app.staticTexts["Brake fluid"].waitForExistence(timeout: 5))
    }

    /// A position that is not in the schedule yet can be created right from "Log service".
    func testCustomItemFromLogService() {
        openLogService()
        app.buttons["entry.pick"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Radiator flush")
        let create = app.buttons["picker.createCustom"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        let done = app.buttons["picker.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()
        XCTAssertTrue(app.staticTexts["Radiator flush"].waitForExistence(timeout: 5))

        // Saving without date and odometer is not allowed: errors are shown, the form stays open.
        app.buttons["entry.save"].tap()
        XCTAssertTrue(app.staticTexts["Please fill this in"].waitForExistence(timeout: 3))
    }

    /// A new odometer above the next oil change (237 000 km in demo data) makes it overdue on Home and in the Schedule.
    func testOdometerUpdateRecalculatesEverywhere() {
        app.buttons["home.update"].tap()
        let field = app.textFields["odometer.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("240000")
        app.buttons["odometer.save"].tap()

        // "240,000 km" with a non-breaking space before "km".
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "240,000")).firstMatch
            .waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Overdue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Engine oil"].exists)

        app.tabBars.buttons["Schedule"].tap()
        XCTAssertTrue(app.staticTexts["Engine oil"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "was due")).firstMatch
            .waitForExistence(timeout: 5))
    }

    /// Every list scrolls, and tapping a row opens its form: Home, History (both modes), Schedule, Expenses.
    func testListsScrollAndRowsOpen() {
        func assertScrolls(_ name: String) {
            let first = app.cells.firstMatch
            XCTAssertTrue(first.waitForExistence(timeout: 5), "\(name): no rows")
            let before = first.frame.minY
            app.swipeUp(velocity: .slow)
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            XCTAssertNotEqual(app.cells.firstMatch.frame.minY, before, "\(name): list doesn't scroll")
            app.swipeDown(velocity: .slow)
            app.swipeDown(velocity: .slow)
        }
        func assertRowOpens(_ name: String, cell index: Int, form identifier: String) {
            let cell = app.cells.element(boundBy: index)
            XCTAssertTrue(cell.waitForExistence(timeout: 5), "\(name): no row \(index)")
            cell.tap()
            let save = app.buttons[identifier]
            XCTAssertTrue(save.waitForExistence(timeout: 5), "\(name): tapping a row doesn't open the form")
            app.buttons["Cancel"].firstMatch.tap()
            XCTAssertFalse(save.waitForExistence(timeout: 2), "\(name): the form doesn't close")
        }

        assertScrolls("Home")
        let overdueRow = app.staticTexts["LPG filters"].firstMatch
        XCTAssertTrue(overdueRow.waitForExistence(timeout: 5))
        overdueRow.tap()
        XCTAssertTrue(app.buttons["item.save"].waitForExistence(timeout: 5), "Home: tapping a row doesn't open the item")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertFalse(app.buttons["item.save"].waitForExistence(timeout: 2))

        app.tabBars.buttons["History"].tap()
        assertScrolls("History by date")
        assertRowOpens("History by date", cell: 1, form: "entry.save")
        app.buttons["By item"].tap()
        let row = app.cells.element(boundBy: 1)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.navigationBars.buttons["History"].waitForExistence(timeout: 5), "History by item: row doesn't open")
        app.navigationBars.buttons["History"].tap()

        app.tabBars.buttons["Schedule"].tap()
        assertScrolls("Schedule")
        assertRowOpens("Schedule", cell: 0, form: "item.save")

        app.tabBars.buttons["Expenses"].tap()
        app.buttons["All"].firstMatch.tap()
        assertScrolls("Expenses")
    }

    /// Selection mode in History: select two entries, delete them, they're gone.
    func testHistoryMultiSelectDelete() {
        app.tabBars.buttons["History"].tap()
        let select = app.buttons["history.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        let before = app.cells.count
        select.tap()
        app.cells.element(boundBy: 1).tap()
        app.cells.element(boundBy: 2).tap()
        let action = app.buttons["select.action"]
        XCTAssertTrue(action.waitForExistence(timeout: 3))
        XCTAssertEqual(action.label, "Delete (2)")
        action.tap()
        let confirm = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        let deadline = Date().addingTimeInterval(5)
        while app.cells.count != before - 2 && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        XCTAssertEqual(app.cells.count, before - 2)
    }
}
