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
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language == "uk" ? "uk_UA" : language,
                               "-settings.language", language, "-settings.theme", theme, "-demo", "-startTab", tab] + extra
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
        // Scrolling dismisses the keyboard; swiping down could close a sheet.
        if app.keyboards.count > 0 { app.swipeUp(velocity: .slow) }
        pause(0.5)
    }

    /// Scrolls down until the element appears (lists load rows lazily), then taps it.
    @discardableResult
    private func tapScrolling(_ id: String) -> Bool {
        let el = app.descendants(matching: .any)[id].firstMatch
        for _ in 0..<10 {
            if el.exists && el.isHittable { break }
            app.swipeUp(velocity: .slow)
        }
        guard el.exists else { return false }
        el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        pause()
        return true
    }

    /// "Intervals and last replacement": "I don't know — from today", then the usual interval in every empty field.
    private func fillBulkSetup() {
        let dontKnow = app.switches.firstMatch
        if dontKnow.waitForExistence(timeout: 3) {
            dontKnow.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            pause()
        }
        for _ in 0..<5 {
            for field in app.textFields.allElementsBoundByIndex where field.isHittable {
                let placeholder = field.placeholderValue ?? ""
                let value = field.value as? String ?? ""
                let digits = placeholder.filter(\.isNumber)
                guard !digits.isEmpty, value.isEmpty || value == placeholder else { continue }
                field.tap()
                field.typeText(digits)
            }
            app.swipeUp(velocity: .slow)
        }
        pause()
    }

    // MARK: Tour


    func test01Onboarding() {
        launch(["-demoOnboarding"])
        snap("01-onboarding-welcome")
        scrollDown()
        snap("02-onboarding-welcome-bottom")
        tap("onb.next", byCoordinate: true)
        snap("03-onboarding-car")
        scrollDown()
        tap("onb.next", byCoordinate: true)
        app.swipeDown(velocity: .slow)
        pause()
        snap("04-onboarding-car-errors")
        let fields = app.textFields
        type(into: fields.element(boundBy: 0), "Škoda Octavia")
        type(into: fields.element(boundBy: 2), "228100")
        type(into: fields.element(boundBy: 3), "1500")
        hideKeyboard()
        scrollDown()
        tap("onb.next", byCoordinate: true)
        pause(1.5)
        snap("05-onboarding-items")
        if tap("onb.import") {
            snap("06-onboarding-import")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            pause()
        }
        tap("check.Моторне масло")
        tap("check.Масляний фільтр")
        tap("check.Повітряний фільтр")
        snap("07-onboarding-items-picked")
        tap("catalog.next", byCoordinate: true)
        snap("08-onboarding-intervals")
        fillBulkSetup()
        tap("bulk.save", byCoordinate: true)
        pause(1.5)
        snap("09-onboarding-reminders")
        scrollDown(2)
        snap("10-onboarding-reminders-bottom")
        tap("onb.next", byCoordinate: true)
        pause(1.5)
        snap("11-onboarding-notification-permission")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alertButtons = springboard.alerts.firstMatch.buttons
        if alertButtons.count > 1 { alertButtons.element(boundBy: 1).tap() }
        pause(1.5)
        snap("12-onboarding-security")
        tap("onb.next", byCoordinate: true)
        pause(1.5)
        snap("13-onboarding-done-home")
    }

    func test02Home() {
        launch()
        snap("14-home")
        scrollDown()
        snap("15-home-bottom")
        launch()
        if !tap("chip.2") { tap("chip.1") }
        snap("16-home-filtered")
        launch()
        let row = app.cells.element(boundBy: 3)
        if row.waitForExistence(timeout: 4) {
            row.swipeRight(velocity: .slow)
            pause()
            snap("17-home-swipe-done")
        }
        launch(theme: "dark")
        snap("18-home-dark")
    }

    func test03Odometer() {
        launch(["-demoSheet", "odometer"])
        snap("19-odometer")
        type(into: app.textFields["odometer.field"].firstMatch, "200000")
        tap("odometer.save")
        snap("19-odometer-lower-warning")
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
        if tapLabel("Моторне масло") { snap("25-history-item") }
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
            if let current = search.value as? String {
                search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            }
            search.typeText("Промивка радіатора")
            pause()
            snap("35-item-picker-new-custom")
        }
    }

    func test06Schedule() {
        launch(tab: "parts")
        snap("40-schedule")
        scrollDown(2)
        snap("41-schedule-middle")
        scrollDown(2)
        if tap("parts.archive") { scrollDown() }
        snap("42-schedule-bottom")
        launch(tab: "parts")
        if tap("parts.select", byCoordinate: true) {
            app.cells.element(boundBy: 0).tap()
            app.cells.element(boundBy: 1).tap()
            pause()
            snap("43-schedule-select")
            if tap("select.action", byCoordinate: true) { snap("44-schedule-remove-confirm") }
        }
        launch(tab: "parts")
        app.swipeDown()
        let search = app.searchFields.firstMatch
        type(into: search, "фільтр")
        snap("45-schedule-search")
    }

    func test07Items() {
        launch(tab: "parts", ["-demoSheet", "item:engine_oil"])
        snap("46-item-oil")
        scrollDown()
        snap("47-item-oil-middle")
        scrollDown(2)
        snap("48-item-oil-bottom")
        launch(tab: "parts", ["-demoSheet", "item:seasonal_tires"])
        snap("49-item-season")
        launch(tab: "parts", ["-demoSheet", "item:insurance"])
        snap("50-item-valid-until")
        launch(tab: "parts", ["-demoSheet", "newItem"])
        snap("51-item-new")
        tap("item.save")
        snap("52-item-new-errors")
        launch(tab: "parts", ["-demoSheet", "item:custom"])
        snap("53-item-custom")
        let name = app.textFields.firstMatch
        if name.waitForExistence(timeout: 3) {
            name.tap()
            name.typeText(" і бачка")
            tap("item.save", byCoordinate: true)
            snap("54-item-rename-question")
        }
    }

    func test08AddItems() {
        launch(tab: "parts", ["-demoSheet", "addItems"])
        snap("55-catalog")
        tapScrolling("check.Антифриз")
        tapScrolling("check.Щітки склоочисника")
        snap("56-catalog-picked")
        scrollDown(4)
        snap("57-catalog-bottom")
        tap("catalog.next", byCoordinate: true)
        snap("58-catalog-intervals")
        scrollDown()
        snap("59-catalog-intervals-bottom")
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
        launch(tab: "assistant", ["-demoQuestion", "Скільки коштувало масло?"])
        snap("74-assistant-price")
        launch(tab: "assistant", ["-demoQuestion", "Номер масляного фільтра"])
        snap("75-assistant-part-number")
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
        if tap("settings.importLink") { snap("87-import") }
        launch(tab: "settings", ["-demoImportText",
                                 "12.03.2024 185000 масло, фільтр салону | 05.2023 170 тис колодки передні | жовт 2022 158к ГРМ + помпа | 2021 радіатор"])
        scrollDown(2)
        if tap("settings.importLink") {
            snap("88-import-text")
            if tap("import.parse") { snap("89-import-preview") }
        }
    }
}
