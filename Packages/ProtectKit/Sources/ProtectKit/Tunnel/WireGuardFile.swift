import Foundation

/// Checks dropped/pasted data before it reaches the Go parser.
/// Messages describe the problem only; they never quote file content (it holds keys).
public enum WireGuardFile {
    public static let maxBytes = 64 * 1024

    public enum Problem: Error, Equatable, LocalizedError {
        case empty
        case tooLarge
        case notText

        public var errorDescription: String? {
            switch self {
            case .empty: return "Die Datei ist leer."
            case .tooLarge: return "Die Datei ist zu groß für eine WireGuard-Konfiguration."
            case .notText: return "Die Datei ist keine Textdatei."
            }
        }
    }

    public static func text(from data: Data) -> Result<String, Problem> {
        guard !data.isEmpty else { return .failure(.empty) }
        guard data.count <= maxBytes else { return .failure(.tooLarge) }
        guard let text = String(data: data, encoding: .utf8), !text.contains("\u{0}") else {
            return .failure(.notText)
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.empty) }
        return .success(text)
    }
}
