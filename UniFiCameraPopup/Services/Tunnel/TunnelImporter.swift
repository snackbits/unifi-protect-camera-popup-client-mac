import Foundation
import ProtectKit

/// Validates a dropped, picked or pasted WireGuard config and stores it.
@MainActor
enum TunnelImporter {
    struct Outcome: Equatable {
        let summary: TunnelConfigSummary
        /// Non-blocking hint, e.g. the console is not inside AllowedIPs.
        let warning: String?
    }

    enum Failure: LocalizedError, Equatable {
        case file(WireGuardFile.Problem)
        case invalid(String)
        case keychain

        var errorDescription: String? {
            switch self {
            case .file(let problem): return problem.errorDescription
            case .invalid(let message): return "Keine gültige WireGuard-Datei: \(message)"
            case .keychain: return "Der Schlüsselbund hat die Konfiguration nicht angenommen."
            }
        }
    }

    static let pastedFileName = "Eingefügte Konfiguration"

    static func importData(_ data: Data, fileName: String) -> Result<Outcome, Failure> {
        switch WireGuardFile.text(from: data) {
        case .failure(let problem):
            return .failure(.file(problem))
        case .success(let text):
            switch TunnelController.shared.parse(text) {
            case .invalid(let message):
                return .failure(.invalid(message))
            case .valid(let summary):
                // Saved only after the parser accepted it: a broken file never replaces a working one.
                guard TunnelStore.shared.save(config: text, fileName: fileName, summary: summary) else {
                    return .failure(.keychain)
                }
                let warning = TunnelImportCheck.warning(consoleHost: SettingsStore.shared.protectHost, summary: summary)
                return .success(Outcome(summary: summary, warning: warning))
            }
        }
    }
}
