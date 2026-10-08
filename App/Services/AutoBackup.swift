import Foundation
import SwiftData
import CarCareCore

/// Weekly automatic backup: the same JSON as "Export backup", saved to the app's iCloud Drive folder when iCloud
/// is available (iCloud build), otherwise to the app's folder in Files → On My iPhone. The last 5 files are kept.
/// Home shows a reminder when there was no backup (automatic or manual) for 14 days.
@MainActor
enum AutoBackup {
    static let everyDays = 7
    static let remindAfterDays = 14
    static let keep = 5

    private static weak var lastContext: ModelContext?

    static func isOverdue(hasData: Bool, settings: AppSettings, now: Date = Date()) -> Bool {
        guard hasData else { return false }
        guard let last = settings.lastBackup else { return true }
        return OdometerRules.daysSince(last, now: now, calendar: Fmt.calendar) >= remindAfterDays
    }

    /// Called on launch and when the app comes to the foreground.
    static func runIfNeeded(_ context: ModelContext) {
        lastContext = context
        let settings = AppSettings.shared
        if let last = settings.lastBackup,
           OdometerRules.daysSince(last, now: Date(), calendar: Fmt.calendar) < everyDays { return }
        write(context)
    }

    /// "Back up now" from the Home reminder or Settings.
    static func runNow(force: Bool) {
        guard let context = lastContext else { return }
        write(context)
    }

    private static func write(_ context: ModelContext) {
        let snapshot = SnapshotBuilder.fetch(context)
        guard !snapshot.entries.isEmpty || !snapshot.items.isEmpty else { return }
        guard let data = try? BackupCodec.encode(snapshot, exportedAt: Date()) else { return }
        let name = BackupCodec.suggestedFileName(date: Date(), calendar: Fmt.calendar)
        DispatchQueue.global(qos: .utility).async {
            // Looking up the iCloud container can take a moment, so it's done off the main thread.
            let iCloud = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
                .appendingPathComponent("Documents/Backups", isDirectory: true)
            let local = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Backups", isDirectory: true)
            guard let folder = iCloud ?? local else { return }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: folder.appendingPathComponent(name), options: .atomic)
                prune(folder)
                let location = iCloud != nil ? "icloud" : "local"
                DispatchQueue.main.async {
                    AppSettings.shared.lastBackupTime = Date().timeIntervalSince1970
                    AppSettings.shared.backupLocation = location
                }
            } catch {
                print("Auto backup failed: \(error)")
            }
        }
    }

    /// Keeps the newest `keep` backup files.
    nonisolated private static func prune(_ folder: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let backups = files.filter { $0.lastPathComponent.hasPrefix("CarCareLog-backup-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in backups.dropFirst(keep) { try? FileManager.default.removeItem(at: old) }
    }
}
