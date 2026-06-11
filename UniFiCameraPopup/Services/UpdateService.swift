import AppKit
import Combine
import CryptoKit
import Foundation

/// Manifest served by the relay server at `AppConfig.updateManifestURL`
/// (the same file as `server/version.json`, written by `build-release.sh`).
struct UpdateManifest: Decodable {
    let versionId: String
    let buildNumber: Int
    let shortVersion: String?
    let url: String
    let sha256: String
    let signature: String
    let notes: String?
}

/// Lifecycle of the in-app updater, surfaced to the menu UI.
enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(buildNumber: Int, shortVersion: String?)
    case downloading
    case installing
    case failed(String)
}

/// Checks the relay server for a newer build, verifies its integrity and
/// authenticity (SHA-256 + Ed25519 signature), and installs it in place.
///
/// No paid services, certificates, or notarization are required: the app is
/// distributed as an ad-hoc signed `.zip`, downloaded over HTTPS, and swapped
/// in by a small detached helper after the app quits. Authenticity is
/// guaranteed by an Ed25519 signature whose private key never leaves the
/// developer's machine, so even a compromised server cannot push a forged build.
@MainActor
final class UpdateService: NSObject, ObservableObject {
    @Published private(set) var state: UpdateState = .idle

    /// Set when a newer build than the running one is available.
    @Published private(set) var availableManifest: UpdateManifest?

    private var isBusy = false

    var updateAvailable: Bool { availableManifest != nil }

    /// Fetches the manifest and compares it to the running build.
    func checkForUpdates() async {
        guard !isBusy else { return }
        guard !AppConfig.updatePublicKey.isEmpty,
              let manifestURL = URL(string: AppConfig.updateManifestURL) else {
            return
        }

        if availableManifest == nil { state = .checking }

        do {
            var request = URLRequest(url: manifestURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError.badResponse
            }

            let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)

            if manifest.buildNumber > AppConfig.buildNumber,
               manifest.versionId != AppConfig.buildVersionId,
               !manifest.signature.isEmpty {
                availableManifest = manifest
                state = .available(buildNumber: manifest.buildNumber, shortVersion: manifest.shortVersion)
            } else {
                availableManifest = nil
                state = .upToDate
            }
        } catch {
            // A failed check is non-fatal; keep any previously found update.
            if availableManifest == nil { state = .idle }
            NSLog("Update check failed: \(error.localizedDescription)")
        }
    }

    /// Downloads, verifies and installs the available update, then relaunches.
    func installUpdate() async {
        guard !isBusy, let manifest = availableManifest else { return }
        guard let downloadURL = URL(string: manifest.url) else {
            state = .failed("Ungültige Download-URL.")
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            state = .downloading
            var request = URLRequest(url: downloadURL)
            request.timeoutInterval = 120
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError.badResponse
            }

            try verify(data: data, against: manifest)

            state = .installing
            let newAppURL = try unpack(data: data)
            try validateBundleIdentifier(of: newAppURL)
            try swapAndRelaunch(newApp: newAppURL)
            // swapAndRelaunch terminates the app; control does not return.
        } catch {
            state = .failed(humanMessage(for: error))
            NSLog("Update install failed: \(error.localizedDescription)")
        }
    }

    func dismissError() {
        if case .failed = state {
            state = availableManifest == nil ? .idle : .available(
                buildNumber: availableManifest!.buildNumber,
                shortVersion: availableManifest!.shortVersion
            )
        }
    }

    // MARK: - Verification

    private func verify(data: Data, against manifest: UpdateManifest) throws {
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        guard hex.caseInsensitiveCompare(manifest.sha256) == .orderedSame else {
            throw UpdateError.checksumMismatch
        }

        guard let publicKeyData = Data(base64Encoded: AppConfig.updatePublicKey),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData) else {
            throw UpdateError.invalidPublicKey
        }

        guard let signatureData = Data(base64Encoded: manifest.signature),
              publicKey.isValidSignature(signatureData, for: data) else {
            throw UpdateError.signatureInvalid
        }
    }

    // MARK: - Unpacking

    private func unpack(data: Data) throws -> URL {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory
            .appendingPathComponent("UniFiCameraPopupUpdate-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)

        let zipURL = workDir.appendingPathComponent("update.zip")
        try data.write(to: zipURL)

        let extractDir = workDir.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

        // ditto correctly preserves the bundle's symlinks (e.g. inside the
        // VLCKit framework) and resource forks that plain unzip can mangle.
        try runProcess("/usr/bin/ditto", ["-x", "-k", zipURL.path, extractDir.path])

        let entries = try fm.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil)
        guard let appURL = entries.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.noAppInArchive
        }
        return appURL
    }

    private func validateBundleIdentifier(of appURL: URL) throws {
        guard let bundle = Bundle(url: appURL),
              let identifier = bundle.bundleIdentifier,
              identifier == Bundle.main.bundleIdentifier else {
            throw UpdateError.bundleIdentifierMismatch
        }
    }

    // MARK: - Install (in place, with admin fallback)

    private func swapAndRelaunch(newApp: URL) throws {
        let destination = Bundle.main.bundleURL
        let parent = destination.deletingLastPathComponent()
        let fm = FileManager.default

        let canWriteInPlace = fm.isWritableFile(atPath: parent.path)
            && (!fm.fileExists(atPath: destination.path) || fm.isWritableFile(atPath: destination.path))

        let dest = destination.path
        let new = newApp.path
        let pid = ProcessInfo.processInfo.processIdentifier

        if canWriteInPlace {
            // A detached helper waits for this process to exit, swaps the bundle
            // and relaunches – no password prompt needed.
            let script = """
            #!/bin/sh
            while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done
            /bin/rm -rf \(shellQuote(dest))
            /usr/bin/ditto \(shellQuote(new)) \(shellQuote(dest))
            /usr/bin/xattr -dr com.apple.quarantine \(shellQuote(dest)) 2>/dev/null
            /usr/bin/open \(shellQuote(dest))
            """
            try launchDetachedShell(script)
        } else {
            // The bundle lives in a location the user cannot write to
            // (e.g. /Applications owned by another admin). Copy it with an
            // authenticated prompt while we are still running, then let a
            // detached helper relaunch us once we quit.
            try runPrivilegedSwap(source: new, destination: dest)
            let script = """
            #!/bin/sh
            while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done
            /usr/bin/open \(shellQuote(dest))
            """
            try launchDetachedShell(script)
        }

        NSApp.terminate(nil)
    }

    private func runPrivilegedSwap(source: String, destination: String) throws {
        let shellCommand =
            "/bin/rm -rf \(shellQuote(destination)) && "
            + "/usr/bin/ditto \(shellQuote(source)) \(shellQuote(destination)) && "
            + "/usr/bin/xattr -dr com.apple.quarantine \(shellQuote(destination))"

        // Escape for embedding inside an AppleScript string literal.
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escaped)\" with administrator privileges"

        guard let script = NSAppleScript(source: appleScript) else {
            throw UpdateError.installFailed("AppleScript konnte nicht erstellt werden.")
        }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unbekannter Fehler"
            throw UpdateError.installFailed(message)
        }
    }

    private func launchDetachedShell(_ script: String) throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("unifi-popup-update-\(UUID().uuidString).sh")
        try Data(script.utf8).write(to: scriptURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path]
        try process.run()
        // Intentionally do not wait: the helper must outlive this process.
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func runProcess(_ launchPath: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let errData = pipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errData, encoding: .utf8) ?? ""
            throw UpdateError.installFailed("\(launchPath) fehlgeschlagen: \(message)")
        }
    }

    private func humanMessage(for error: Error) -> String {
        if let updateError = error as? UpdateError {
            return updateError.localizedDescription
        }
        return error.localizedDescription
    }
}

enum UpdateError: LocalizedError {
    case badResponse
    case checksumMismatch
    case invalidPublicKey
    case signatureInvalid
    case noAppInArchive
    case bundleIdentifierMismatch
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return "Server antwortete unerwartet."
        case .checksumMismatch:
            return "Prüfsumme der heruntergeladenen Datei stimmt nicht."
        case .invalidPublicKey:
            return "Update-Signaturschlüssel ist ungültig."
        case .signatureInvalid:
            return "Signatur der heruntergeladenen Datei ist ungültig."
        case .noAppInArchive:
            return "Im Update-Archiv wurde keine App gefunden."
        case .bundleIdentifierMismatch:
            return "Das Update gehört nicht zu dieser App."
        case .installFailed(let detail):
            return "Installation fehlgeschlagen: \(detail)"
        }
    }
}
