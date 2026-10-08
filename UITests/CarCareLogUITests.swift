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
        app.buttons["addMenu"].firstMatch.tap()
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

        // Cancel in the search field keeps the selection.
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].firstMatch.tap() }
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()

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
        XCTAssertTrue(app.staticTexts["Required"].waitForExistence(timeout: 3))
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
        XCTAssertTrue(app.staticTexts["Overdue"].firstMatch.waitForExistence(timeout: 5))
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
