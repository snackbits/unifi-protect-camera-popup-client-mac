import AppKit
import Foundation
import ProtectKit

/// Owns the Protect API client for the configured console and caches cameras/stream URLs.
@MainActor
final class ProtectSession: ObservableObject {
    static let shared = ProtectSession()

    @Published private(set) var cameras: [ProtectCamera] = []
    @Published private(set) var lastError: String?
    /// Replaced by `reconnect()`. `ProtectEventService` observes this to restart its
    /// event loop with the new client; a replaced client is always invalidated first.
    @Published private(set) var client: ProtectClient?
    private var streamCache: [String: String] = [:]
    private var snapshotCache: [String: (image: NSImage, date: Date)] = [:]
    private let settings = SettingsStore.shared

    private init() {}

    /// Rebuilds the client from current settings (after onboarding or settings changes).
    func reconnect() {
        streamCache = [:]
        snapshotCache = [:]
        lastError = nil
        client?.invalidate()
        guard settings.isProtectConfigured else {
            client = nil
            cameras = []
            return
        }
        let host = settings.protectHost
        client = ProtectClient(
            host: host,
            apiKey: settings.protectAPIKey,
            pinnedFingerprint: settings.protectCertificateFingerprint,
            onNewFingerprint: { fp in
                Task { @MainActor in
                    // A late handshake of a replaced client must not pin another console.
                    guard SettingsStore.normalizedHost(SettingsStore.shared.protectHost)
                            == SettingsStore.normalizedHost(host) else { return }
                    SettingsStore.shared.protectCertificateFingerprint = fp
                }
            }
        )
        Task { await refreshCameras() }
    }

    func refreshCameras() async {
        guard let client else { return }
        do {
            let result = try await client.cameras()
            guard client === self.client else { return }
            cameras = result
            lastError = nil
        } catch {
            guard client === self.client else { return }
            lastError = error.localizedDescription
        }
    }

    /// Manual RTSP URL wins (hidden "Erweitert" field); otherwise ask Protect.
    func streamURL(for mapping: WebhookMapping) async -> String? {
        let manual = mapping.rtspsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !manual.isEmpty { return StreamURL.normalizedRTSP(manual) }
        guard let cameraId = mapping.protectCameraId, let client else { return nil }
        if let cached = streamCache[cameraId] { return cached }
        do {
            let url = try await client.rtspURL(cameraId: cameraId)
            if let url, client === self.client { streamCache[cameraId] = url }
            return url
        } catch {
            if client === self.client { lastError = error.localizedDescription }
            return nil
        }
    }

    /// Camera still for thumbnails, cached for `maxAge` seconds (0 = always fresh).
    /// nil without Protect, for unknown cameras or on any error.
    func snapshot(cameraId: String, maxAge: TimeInterval = 60) async -> NSImage? {
        if let cached = snapshotCache[cameraId], Date().timeIntervalSince(cached.date) < maxAge {
            return cached.image
        }
        guard let client else { return nil }
        guard let data = try? await client.snapshot(cameraId: cameraId),
              let image = NSImage(data: data) else { return nil }
        if client === self.client {
            snapshotCache[cameraId] = (image, Date())
        }
        return image
    }
}
