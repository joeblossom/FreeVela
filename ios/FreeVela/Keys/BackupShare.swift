import UIKit

/// Shares vela-backup.json with the system share sheet and reports whether it was saved or sent.
/// (ShareLink can't say when a share completes, and the app needs to know a backup exists.)
@MainActor
enum BackupShare {
    static func present(_ keys: KeyStore, onDone: @escaping (Bool) -> Void = { _ in }) {
        guard let file = try? VelaBackup.file(for: keys.bikes),
              let top = topController() else { onDone(false); return }
        let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, completed, _, _ in
            if completed { keys.markBackedUp(keys.bikes.map(\.id)) }
            onDone(completed)
        }
        sheet.popoverPresentationController?.sourceView = top.view
        top.present(sheet, animated: true)
    }

    private static func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}
