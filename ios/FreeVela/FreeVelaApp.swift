import SwiftUI

@main
struct FreeVelaApp: App {
    @StateObject private var keys = KeyStore()
    @StateObject private var log: LabLog
    @StateObject private var link: BikeLink
    /// App-wide so an update keeps its progress if you leave and reopen the screen.
    @StateObject private var updater = FirmwareUpdater()

    init() {
        let log = LabLog()
        _log = StateObject(wrappedValue: log)
        _link = StateObject(wrappedValue: BikeLink(log: log))
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(keys)
                .environmentObject(log)
                .environmentObject(link)
                .environmentObject(updater)
        }
    }
}
