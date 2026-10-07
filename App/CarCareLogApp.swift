import SwiftUI
import SwiftData
import CarCareCore

@main
struct CarCareLogApp: App {
    @StateObject private var persistence = Persistence(inMemory: DemoMode.isOn)
    @StateObject private var settings = AppSettings.shared
    @StateObject private var lock = AppLock()
    @StateObject private var router = Router()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(persistence)
                .environmentObject(settings)
                .environmentObject(lock)
                .environmentObject(router)
                .environment(\.locale, L10n.locale)
                .preferredColorScheme(settings.colorScheme)
                // Rebuild the whole UI when the in-app language changes.
                .id(settings.language)
        }
        .modelContainer(persistence.container)
    }
}

/// Tab selection and every form sheet, shared so any screen, the Home empty state and widget deep links
/// can open them.
final class Router: ObservableObject {
    enum Tab: Hashable { case home, history, parts, assistant, settings }

    /// Values for a new item, e.g. after "This is a different part" on rename.
    struct ItemDraft {
        var name = ""
        var intervalKm: Int?
        var intervalMonths: Int?
    }

    enum Sheet: Identifiable {
        /// "Log service" with these items preselected.
        case logService([UUID])
        case editEntry(ServiceEntry)
        case newItem(ItemDraft)
        case item(Item)
        case odometer

        var id: String {
            switch self {
            case .logService(let ids): return "log-" + ids.map(\.uuidString).joined(separator: ",")
            case .editEntry(let e): return "entry-" + e.uuid.uuidString
            case .newItem(let d): return "new-" + d.name
            case .item(let i): return "item-" + i.uuid.uuidString
            case .odometer: return "odometer"
            }
        }
    }

    @Published var tab: Tab = DemoMode.isOn ? DemoMode.startTab : .home
    @Published var sheet: Sheet?

    /// Replaces the current sheet with another one (e.g. from an item card to "Log service").
    func open(_ next: Sheet) {
        if sheet == nil {
            sheet = next
        } else {
            sheet = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { self.sheet = next }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var lock: AppLock
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var persistence: Persistence
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @State private var didLaunch = false

    var body: some View {
        Group {
            if settings.onboardingDone {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .overlay {
            if lock.isLocked { LockView() }
        }
        .onAppear {
            guard !didLaunch else { return }
            didLaunch = true
            if DemoMode.isOn { DemoMode.seed(context) }
            lock.lockIfEnabled(settings.faceIDEnabled)
            lock.unlockIfNeeded(enabled: settings.faceIDEnabled)
            DataEvents.appDidBecomeActive(context)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                lock.lockIfEnabled(settings.faceIDEnabled)
            case .active:
                lock.unlockIfNeeded(enabled: settings.faceIDEnabled)
                DataEvents.appDidBecomeActive(context)
                Task { await persistence.refreshAccountStatus() }
            default:
                break
            }
        }
        .onOpenURL { url in
            // From the widget: carcarelog://log?items=<uuid>,<uuid> or carcarelog://upcoming
            guard url.scheme == "carcarelog" else { return }
            router.tab = .home
            if url.host == "log" {
                let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "items" }?.value ?? ""
                let ids = value.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
                router.open(.logService(ids))
            }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var router: Router

    var body: some View {
        TabView(selection: $router.tab) {
            HomeView()
                .tabItem { Label(L10n.t("tab.home"), systemImage: "house") }
                .tag(Router.Tab.home)
            HistoryView()
                .tabItem { Label(L10n.t("tab.history"), systemImage: "clock.arrow.circlepath") }
                .tag(Router.Tab.history)
            PartsView()
                .tabItem { Label(L10n.t("tab.parts"), systemImage: "list.bullet.clipboard") }
                .tag(Router.Tab.parts)
            AssistantView()
                .tabItem { Label(L10n.t("tab.assistant"), systemImage: "bubble.left.and.text.bubble.right") }
                .tag(Router.Tab.assistant)
            SettingsView()
                .tabItem { Label(L10n.t("tab.settings"), systemImage: "gearshape") }
                .tag(Router.Tab.settings)
        }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .logService(let ids): EntryEditorView(entry: nil, preselected: ids)
            case .editEntry(let entry): EntryEditorView(entry: entry, preselected: [])
            case .newItem(let draft): ItemEditorView(item: nil, draft: draft)
            case .item(let item): ItemEditorView(item: item, draft: Router.ItemDraft())
            case .odometer: OdometerUpdateView()
            }
        }
    }
}

/// "+" in the top right corner of Home, History and Schedule.
struct AddMenuButton: View {
    @EnvironmentObject private var router: Router

    var body: some View {
        Menu {
            Button {
                router.open(.logService([]))
            } label: {
                Label(L10n.t("add.logService"), systemImage: "checkmark.circle")
            }
            Button {
                router.open(.newItem(Router.ItemDraft()))
            } label: {
                Label(L10n.t("add.item"), systemImage: "plus.square")
            }
        } label: {
            Image(systemName: "plus").font(.title3.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(L10n.t("add.menu"))
    }
}
struct LockView: View {
    @EnvironmentObject private var lock: AppLock
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("CarCare Log").font(.title2.bold())
                Button {
                    lock.unlockIfNeeded(enabled: settings.faceIDEnabled)
                } label: {
                    Text(L10n.t("lock.unlock")).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 40)
            }
        }
    }
}
