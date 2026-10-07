import Foundation
import SwiftData
import CoreData
#if ICLOUD_YES
import CloudKit
#endif

/// iCloud is a backup/sync layer only: the app works fully on the local store when it is off or failing.
enum ICloudState: Equatable {
    /// Built without iCloud (CC_ICLOUD = NO).
    case disabledInBuild
    case checking
    case active
    case noAccount
    case quotaFull
    case syncError(String)
    /// CloudKit store could not be opened; the app runs on a local-only store.
    case localFallback

    var showsWarning: Bool {
        switch self {
        case .noAccount, .quotaFull, .syncError, .localFallback: return true
        default: return false
        }
    }
}

@MainActor
final class Persistence: ObservableObject {
    static let schema = Schema([Car.self, Item.self, ServiceEntry.self, OdometerReading.self])

    let container: ModelContainer
    @Published private(set) var iCloudState: ICloudState

    private var observer: NSObjectProtocol?

    init(inMemory: Bool = false) {
        if inMemory {
            let config = ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: Self.schema, configurations: config)
            iCloudState = .disabledInBuild
            return
        }
        #if ICLOUD_YES
        let containerID = Bundle.main.object(forInfoDictionaryKey: "CCICloudContainer") as? String ?? ""
        let cloudConfig = ModelConfiguration(schema: Self.schema, cloudKitDatabase: .private(containerID))
        if let c = try? ModelContainer(for: Self.schema, configurations: cloudConfig) {
            container = c
            iCloudState = .checking
            observeSyncEvents()
            Task { await self.refreshAccountStatus() }
            return
        }
        container = Self.makeLocalContainer()
        iCloudState = .localFallback
        #else
        container = Self.makeLocalContainer()
        iCloudState = .disabledInBuild
        #endif
    }

    private static func makeLocalContainer() -> ModelContainer {
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        if let c = try? ModelContainer(for: schema, configurations: config) { return c }
        // Last resort so the app still opens; data would not persist.
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: memory)
    }

    #if ICLOUD_YES
    func refreshAccountStatus() async {
        do {
            let status = try await CKContainer.default().accountStatus()
            switch status {
            case .available:
                if case .checking = iCloudState { iCloudState = .active }
                if case .noAccount = iCloudState { iCloudState = .active }
            default:
                iCloudState = .noAccount
            }
        } catch {
            iCloudState = .noAccount
        }
    }

    private func observeSyncEvents() {
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event, event.endDate != nil else { return }
            let newState: ICloudState
            if let error = event.error {
                if let ck = error as? CKError, ck.code == .quotaExceeded {
                    newState = .quotaFull
                } else if let ck = error as? CKError, ck.code == .notAuthenticated {
                    newState = .noAccount
                } else {
                    newState = .syncError(error.localizedDescription)
                }
            } else {
                newState = .active
            }
            Task { @MainActor in self?.iCloudState = newState }
        }
    }
    #else
    func refreshAccountStatus() async {}
    #endif
}
