import Foundation

struct LogEntry: Identifiable {
    enum Kind: String { case info = "·", tx = "→", rx = "←", ok = "✓", error = "✗" }
    let id = UUID()
    let time = Date()
    let kind: Kind
    let text: String
}

final class LabLog: ObservableObject {
    @Published private(set) var entries: [LogEntry] = []

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    func add(_ kind: LogEntry.Kind, _ text: String) {
        entries.append(LogEntry(kind: kind, text: text))
    }

    func clear() { entries.removeAll() }

    func line(_ e: LogEntry) -> String {
        "\(Self.clock.string(from: e.time)) \(e.kind.rawValue) \(e.text)"
    }

    /// Plain-text export for sharing. Key bytes are never in here — see BikeLink.describe.
    var exportText: String {
        let header = "FreeVela Lab log — \(ISO8601DateFormatter().string(from: Date()))\n"
        return header + entries.map(line).joined(separator: "\n")
    }
}
