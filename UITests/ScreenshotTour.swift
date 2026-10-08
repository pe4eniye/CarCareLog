import XCTest

/// Walks through every screen, sheet and dialog in demo mode and saves a PNG of each into SHOTS_DIR
/// (set by scripts/take-screenshots.sh as TEST_RUNNER_SHOTS_DIR). Skipped in the regular CI run.
/// A missing element doesn't stop the tour: that screenshot is just not taken.
final class ScreenshotTour: XCTestCase {
    private var app: XCUIApplication!
    private var dir: URL!
    private var language: String { ProcessInfo.processInfo.environment["SHOTS_LANG"] ?? "uk" }

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["SHOTS_DIR"], !path.isEmpty else {
            throw XCTSkip("Screenshot tour runs only from scripts/take-screenshots.sh")
        }
        dir = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        continueAfterFailure = true
        app = XCUIApplication()
    }

    // MARK: Helpers

    private func launch(tab: String = "home", theme: String = "light", _ extra: [String] = []) {
        app.terminate()
        // Settings first (UserDefaults argument domain), demo flags last.
        app.launchArguments = ["-settings.language", language, "-settings.theme", theme, "-demo", "-startTab", tab] + extra
        app.launch()
        pause(2.5)
    }

    private func pause(_ seconds: Double = 1.2) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func snap(_ name: String) {
        pause(0.8)
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: dir.appendingPathComponent("\(language)-\(name).png"))
    }

    /// Taps the first element with this identifier among buttons, cells, texts…; false if not found.
    @discardableResult
    private func tap(_ id: String, timeout: Double = 4, byCoordinate: Bool = false) -> Bool {
        let el = app.descendants(matching: .any)[id].firstMatch
        guard el.waitForExistence(timeout: timeout) else { return false }
        if byCoordinate || !el.isHittable {
            el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else {
            el.tap()
        }
        pause()
        return true
    }

    @discardableResult
    private func tapLabel(_ label: String, timeout: Double = 4) -> Bool {
        let el = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
        guard el.waitForExistence(timeout: timeout) else { return false }
        el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        pause()
        return true
    }

    private func type(into field: XCUIElement, _ text: String) {
        guard field.waitForExistence(timeout: 4) else { return }
        field.tap()
        field.typeText(text)
        pause(0.5)
    }

    private func scrollDown(_ times: Int = 1) {
        for _ in 0..<times { app.swipeUp(velocity: .slow) }
        pause()
    }

    private func tabBar(_ index: Int) {
        let button = app.tabBars.buttons.element(boundBy: index)
        if button.waitForExistence(timeout: 4) { button.tap() }
        pause()
    }

    private func hideKeyboard() {
        if app.keyboards.count > 0 { app.swipeDown(velocity: .fast) }
        pause(0.5)
    }

    // MARK: Tour

    func test01Onboarding() {
        launch(["-demoOnboarding"])
        snap("01-onboarding-car")
        tapLabel("Далі")
        snap("02-onboarding-car-errors")
        let fields = app.textFields
        type(into: fields.element(boundBy: 0), "Škoda Octavia")
        type(into: fields.element(boundBy: 2), "228100")
        type(into: fields.element(boundBy: 3), "1500")
        hideKeyboard()
        if !tapLabel("Далі", timeout: 2) {
            scrollDown()
            tapLabel("Далі")
        }
        pause(1.5)
        snap("03-onboarding-items")
        tap("check.Антифриз")
        tap("check.Щітки склоочисника")
        snap("04-onboarding-items-picked")
        tap("catalog.next", byCoordinate: true)
        snap("05-onboarding-intervals")
        tap("bulk.save", byCoordinate: true)
        pause(1.5)
        snap("06-onboarding-next-step")
        tapLabel("Пропустити")
        snap("07-onboarding-last-step")
    }

    func test02Home() {
        launch()
        snap("10-home")
        scrollDown()
        snap("11-home-bottom")
        launch()
        if !tap("chip.2") { tap("chip.1") }
        snap("12-home-filtered")
        launch()
        let row = app.cells.element(boundBy: 3)
        if row.waitForExistence(timeout: 4) {
            row.swipeRight(velocity: .slow)
            pause()
            snap("13-home-swipe-done")
        }
        launch(theme: "dark")
        snap("14-home-dark")
    }

    func test03Odometer() {
        launch(["-demoSheet", "odometer"])
        snap("15-odometer")
        type(into: app.textFields["odometer.field"].firstMatch, "200000")
        tap("odometer.save")
        snap("16-odometer-lower-warning")
    }

    func test04History() {
        launch(tab: "history")
        snap("20-history")
        scrollDown()
        snap("21-history-bottom")
        launch(tab: "history")
        if tap("history.select", byCoordinate: true) {
            app.cells.element(boundBy: 1).tap()
            app.cells.element(boundBy: 2).tap()
            pause()
            snap("22-history-select")
            if tap("select.action", byCoordinate: true) { snap("23-history-delete-confirm") }
        }
        launch(tab: "history")
        tapLabel("За позиціями")
        snap("24-history-by-item")
        let first = app.cells.element(boundBy: 1)
        if first.waitForExistence(timeout: 3) {
            first.tap()
            pause()
            snap("25-history-item")
        }
    }

    func test05Entry() {
        launch(tab: "history", ["-demoSheet", "entry"])
        snap("26-entry-edit")
        scrollDown()
        snap("27-entry-edit-bottom")
        scrollDown(2)
        if tapLabel("Видалити запис") { snap("28-entry-delete-confirm") }

        launch(["-demoSheet", "log"])
        snap("30-log-service")
        tap("entry.save")
        snap("31-log-service-errors")
        launch(["-demoSheet", "log"])
        scrollDown()
        let split = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Розбити")).firstMatch
        if split.waitForExistence(timeout: 3) {
            split.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            pause()
        }
        snap("32-log-service-split-costs")
        launch(["-demoSheet", "log"])
        if tap("entry.pick") {
            snap("33-item-picker")
            let search = app.searchFields.firstMatch
            type(into: search, "гальм")
            snap("34-item-picker-search")
            search.typeText("ування радіатора")
            pause()
            snap("35-item-picker-new-custom")
        }
    }

    func test06Schedule() {
        launch(tab: "parts")
        snap("40-schedule")
        scrollDown(2)
        if tap("parts.archive") { scrollDown() }
        snap("41-schedule-bottom")
        launch(tab: "parts")
        if tap("parts.select", byCoordinate: true) {
            app.cells.element(boundBy: 0).tap()
            app.cells.element(boundBy: 1).tap()
            pause()
            snap("42-schedule-select")
            if tap("select.action", byCoordinate: true) { snap("43-schedule-remove-confirm") }
        }
        launch(tab: "parts")
        app.swipeDown()
        let search = app.searchFields.firstMatch
        type(into: search, "фільтр")
        snap("44-schedule-search")
    }

    func test07Items() {
        launch(tab: "parts", ["-demoSheet", "item:engine_oil"])
        snap("45-item-oil")
        scrollDown()
        snap("46-item-oil-middle")
        scrollDown(2)
        snap("47-item-oil-bottom")
        launch(tab: "parts", ["-demoSheet", "item:seasonal_tires"])
        snap("48-item-season")
        launch(tab: "parts", ["-demoSheet", "item:insurance"])
        snap("49-item-valid-until")
        launch(tab: "parts", ["-demoSheet", "newItem"])
        snap("50-item-new")
        tap("item.save")
        snap("51-item-new-errors")
        launch(tab: "parts", ["-demoSheet", "item:engine_oil"])
        let name = app.textFields.firstMatch
        if name.waitForExistence(timeout: 3) {
            name.tap()
            name.typeText(" Castrol")
            hideKeyboard()
            tap("item.save")
            snap("52-item-rename-question")
        }
    }

    func test08AddItems() {
        launch(tab: "parts", ["-demoSheet", "addItems"])
        snap("53-catalog")
        tap("check.Антифриз")
        tap("check.Щітки склоочисника")
        snap("54-catalog-picked")
        scrollDown(4)
        snap("55-catalog-bottom")
        tap("catalog.next", byCoordinate: true)
        snap("56-catalog-intervals")
        scrollDown()
        snap("57-catalog-intervals-bottom")
    }

    func test09Expenses() {
        launch(tab: "expenses")
        snap("60-expenses-month")
        tapLabel("Рік")
        snap("61-expenses-year")
        scrollDown()
        snap("62-expenses-year-bottom")
        launch(tab: "expenses")
        tapLabel("Усе")
        snap("63-expenses-all")
        scrollDown(2)
        snap("64-expenses-all-bottom")
    }

    func test10Assistant() {
        launch(tab: "assistant")
        snap("70-assistant")
        launch(tab: "assistant", ["-demoQuestion", "Коли я востаннє міняв моторне масло?"])
        snap("71-assistant-last-done")
        launch(tab: "assistant", ["-demoQuestion", "Що замінити на 240 тис?"])
        snap("72-assistant-due-at")
        launch(tab: "assistant", ["-demoQuestion", "Скільки я витратив цього року?"])
        snap("73-assistant-spending")
        launch(tab: "assistant", ["-demoQuestion", "Номер масляного фільтра"])
        snap("74-assistant-part-number")
    }

    func test11Settings() {
        launch(tab: "settings")
        snap("80-settings")
        scrollDown()
        snap("81-settings-middle")
        scrollDown(3)
        snap("82-settings-bottom")
        if tap("settings.wipe") { snap("83-settings-wipe-confirm") }

        launch(tab: "settings")
        if tap("settings.carLink") { snap("84-settings-car") }
        launch(tab: "settings")
        if tap("settings.notificationsLink") {
            snap("85-settings-notifications")
            scrollDown()
            snap("86-settings-notifications-bottom")
        }
        launch(tab: "settings")
        scrollDown(2)
        if tap("settings.importLink") {
            snap("87-import")
            let text = app.textViews["import.text"].firstMatch
            type(into: text, "12.03.2024 185000 масло, фільтр салону\n05.2023 170 тис колодки передні\nжовт 2022 158к ГРМ + помпа")
            hideKeyboard()
            if tap("import.parse") { snap("88-import-preview") }
        }
    }
}
