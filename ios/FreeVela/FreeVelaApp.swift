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
        .themed()
        .onAppear { apply(appearance) }
        .onChange(of: appearance) { apply(appearance) }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-demo") {
                if keys.bikes.isEmpty {
                    let zero = Data(count: 32).base64EncodedString()
                    keys.add([BikeKeys(id: "demo0000", key: zero, releasedKey: Data(repeating: 1, count: 32).base64EncodedString())])
                }
                let args = ProcessInfo.processInfo.arguments
                let off = args.contains("-demoOff")
                link.loadDemoState(rps: off ? 0 : 4.2, assist: off ? (0, 20) : (1, 20))
                return
            }
            #endif
            session.autoConnect()
        }
        .onChange(of: keys.bikes) {
            session.bikesChanged()
            if keys.bikes.isEmpty { onboarded = false }
        }
        .onChange(of: session.selectedID) { session.autoConnect() }
        .onChange(of: link.bluetooth) { session.autoConnect() }
        .onChange(of: scenePhase) { if scenePhase == .active { session.autoConnect() } }
    }

    /// SwiftUI's preferredColorScheme(nil) doesn't undo an earlier light/dark choice, so set the
    /// windows' style directly. Sheets and covers follow; Ride stays dark on its own.
    private func apply(_ appearance: Appearance) {
        let style: UIUserInterfaceStyle = switch appearance {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.windows.forEach { $0.overrideUserInterfaceStyle = style }
        }
    }
}
