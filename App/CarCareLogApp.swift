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

/// Tab selection, shared so the Home empty state and widget deep links can switch tabs.
final class Router: ObservableObject {
    enum Tab: Hashable { case home, history, parts, assistant, settings }
    @Published var tab: Tab = DemoMode.isOn ? DemoMode.startTab : .home
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
            // carcarelog://upcoming from the widget.
            if url.scheme == "carcarelog" { router.tab = .home }
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
                .tabItem { Label(L10n.t("tab.parts"), systemImage: "wrench.and.screwdriver") }
                .tag(Router.Tab.parts)
            AssistantView()
                .tabItem { Label(L10n.t("tab.assistant"), systemImage: "bubble.left.and.text.bubble.right") }
                .tag(Router.Tab.assistant)
            SettingsView()
                .tabItem { Label(L10n.t("tab.settings"), systemImage: "gearshape") }
                .tag(Router.Tab.settings)
        }
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
