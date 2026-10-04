import SwiftUI

@main
struct FreeVelaApp: App {
    @StateObject private var keys: KeyStore
    @StateObject private var log: LabLog
    @StateObject private var link: BikeLink
    /// App-wide so an update keeps its progress if you leave and reopen the screen.
    @StateObject private var updater: FirmwareUpdater
    @StateObject private var session: Session
    @StateObject private var recorder: RideRecorder

    init() {
        let keys = KeyStore(), log = LabLog(), updater = FirmwareUpdater()
        let link = BikeLink(log: log)
        _keys = StateObject(wrappedValue: keys)
        _log = StateObject(wrappedValue: log)
        _link = StateObject(wrappedValue: link)
        _updater = StateObject(wrappedValue: updater)
        _session = StateObject(wrappedValue: Session(keys: keys, link: link, updater: updater))
        _recorder = StateObject(wrappedValue: RideRecorder(link: link))
        // People who had keys before onboarding existed skip it.
        if !keys.bikes.isEmpty { UserDefaults.standard.set(true, forKey: "onboarded") }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(keys)
                .environmentObject(log)
                .environmentObject(link)
                .environmentObject(updater)
                .environmentObject(session)
                .environmentObject(recorder)
        }
    }
}

/// Onboarding until the first bike is connected, then Home. Also keeps looking for the bike.
private struct RootView: View {
    @EnvironmentObject private var keys: KeyStore
    @EnvironmentObject private var link: BikeLink
    @EnvironmentObject private var session: Session
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("appearance") private var appearance: Appearance = .system

    var body: some View {
        Group {
            if onboarded {
                HomeView()
            } else {
                OnboardingView { onboarded = true }
            }
        }
        .preferredColorScheme(appearance.scheme)
        .onAppear { session.autoConnect() }
        .onChange(of: keys.bikes) {
            session.bikesChanged()
            if keys.bikes.isEmpty { onboarded = false }
        }
        .onChange(of: session.selectedID) { session.autoConnect() }
        .onChange(of: link.bluetooth) { session.autoConnect() }
        .onChange(of: scenePhase) { if scenePhase == .active { session.autoConnect() } }
    }
}
