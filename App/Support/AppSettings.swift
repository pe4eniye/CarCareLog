import SwiftUI
import CarCareCore

/// Local, per-device settings (not synced).
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    enum Keys {
        static let language = "settings.language"
        static let theme = "settings.theme"
        static let leadTime = "settings.leadTimeDays"
        static let faceID = "settings.faceID"
        static let onboardingDone = "settings.onboardingDone"
    }

    @AppStorage(Keys.language) var language: String = "uk" {
        didSet { L10n.setLanguage(language); objectWillChange.send() }
    }
    @AppStorage(Keys.theme) var theme: String = "light" { didSet { objectWillChange.send() } }
    @AppStorage(Keys.leadTime) var leadTimeDays: Int = ReminderLeadTime.oneWeek.rawValue {
        didSet { objectWillChange.send() }
    }
    @AppStorage(Keys.faceID) var faceIDEnabled: Bool = false { didSet { objectWillChange.send() } }
    @AppStorage(Keys.onboardingDone) var onboardingDone: Bool = false { didSet { objectWillChange.send() } }

    init() {
        if DemoMode.isOn {
            onboardingDone = !ProcessInfo.processInfo.arguments.contains("-demoOnboarding")
            faceIDEnabled = false
        }
        L10n.setLanguage(language)
    }

    var leadTime: ReminderLeadTime { ReminderLeadTime(rawValue: leadTimeDays) ?? .oneWeek }

    var colorScheme: ColorScheme? {
        switch theme {
        case "dark": return .dark
        case "system": return nil
        default: return .light
        }
    }
}
