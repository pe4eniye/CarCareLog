import SwiftUI
import CarCareCore

/// Accent color of the app (Settings → Theme color).
enum AccentTheme: String, CaseIterable, Identifiable {
    case teal, blue, purple, coral, graphite

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .teal: return Color(red: 0.06, green: 0.55, blue: 0.49)
        case .blue: return Color(red: 0.18, green: 0.44, blue: 0.93)
        case .purple: return Color(red: 0.49, green: 0.36, blue: 0.86)
        case .coral: return Color(red: 0.90, green: 0.38, blue: 0.23)
        case .graphite: return Color(red: 0.23, green: 0.23, blue: 0.24)
        }
    }

    var titleKey: String { "theme." + rawValue }
}

/// Local, per-device settings (not synced).
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    enum Keys {
        static let language = "settings.language"
        static let theme = "settings.theme"
        static let accent = "settings.accent"
        static let currency = "settings.currency"
        static let leadTime = "settings.leadTimeDays"
        static let faceID = "settings.faceID"
        static let onboardingDone = "settings.onboardingDone"
        static let notifyAll = "settings.notify"
        static let notifyService = "settings.notifyService"
        static let notifyOdometer = "settings.notifyOdometer"
        static let notifyBackup = "settings.notifyBackup"
        static let notifyHour = "settings.notifyHour"
        static let notifyMinute = "settings.notifyMinute"
        static let odometerDays = "settings.odometerDays"
        static let lastBackup = "settings.lastBackup"
        static let backupLocation = "settings.backupLocation"
    }

    @AppStorage(Keys.language) var language: String = "uk" {
        didSet { L10n.setLanguage(language); objectWillChange.send() }
    }
    @AppStorage(Keys.theme) var theme: String = "light" { didSet { objectWillChange.send() } }
    @AppStorage(Keys.accent) var accentRaw: String = AccentTheme.teal.rawValue { didSet { objectWillChange.send() } }
    @AppStorage(Keys.currency) var currencyRaw: String = Currency.uah.rawValue { didSet { objectWillChange.send() } }
    @AppStorage(Keys.leadTime) var leadTimeDays: Int = ReminderLeadTime.oneWeek.rawValue {
        didSet { objectWillChange.send() }
    }
    @AppStorage(Keys.faceID) var faceIDEnabled: Bool = false { didSet { objectWillChange.send() } }
    @AppStorage(Keys.onboardingDone) var onboardingDone: Bool = false { didSet { objectWillChange.send() } }

    // Notifications
    @AppStorage(Keys.notifyAll) var notificationsEnabled: Bool = true { didSet { objectWillChange.send() } }
    @AppStorage(Keys.notifyService) var notifyService: Bool = true { didSet { objectWillChange.send() } }
    @AppStorage(Keys.notifyOdometer) var notifyOdometer: Bool = true { didSet { objectWillChange.send() } }
    @AppStorage(Keys.notifyBackup) var notifyBackup: Bool = true { didSet { objectWillChange.send() } }
    @AppStorage(Keys.notifyHour) var notifyHour: Int = ReminderPlanner.fireHour { didSet { objectWillChange.send() } }
    @AppStorage(Keys.notifyMinute) var notifyMinute: Int = 0 { didSet { objectWillChange.send() } }
    /// Odometer reminder every N days; 0 = off.
    @AppStorage(Keys.odometerDays) var odometerDays: Int = OdometerRules.nudgeIntervalDays {
        didSet { objectWillChange.send() }
    }

    // Backups: last automatic or manual backup (seconds since 1970, 0 = never).
    @AppStorage(Keys.lastBackup) var lastBackupTime: Double = 0 { didSet { objectWillChange.send() } }
    /// "icloud" or "local".
    @AppStorage(Keys.backupLocation) var backupLocation: String = "" { didSet { objectWillChange.send() } }

    init() {
        if DemoMode.isOn {
            onboardingDone = !ProcessInfo.processInfo.arguments.contains("-demoOnboarding")
            faceIDEnabled = false
        }
        L10n.setLanguage(language)
    }

    var leadTime: ReminderLeadTime { ReminderLeadTime(rawValue: leadTimeDays) ?? .oneWeek }
    var accent: AccentTheme { AccentTheme(rawValue: accentRaw) ?? .teal }
    var currency: Currency { Currency(rawValue: currencyRaw) ?? .uah }
    var lastBackup: Date? { lastBackupTime > 0 ? Date(timeIntervalSince1970: lastBackupTime) : nil }

    /// The odometer reminder interval that applies right now (0 when off).
    var effectiveOdometerDays: Int { notificationsEnabled && notifyOdometer ? odometerDays : 0 }

    var colorScheme: ColorScheme? {
        switch theme {
        case "dark": return .dark
        case "system": return nil
        default: return .light
        }
    }
}
