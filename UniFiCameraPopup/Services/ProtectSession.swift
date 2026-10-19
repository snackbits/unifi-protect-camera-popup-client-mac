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
    /// Width / height of each camera's picture, learned from snapshots (automatic popup size).
    /// Kept across reconnects: a camera's picture format does not depend on the route.
    @Published private(set) var aspectRatios: [String: Double] = [:]
    private let settings = SettingsStore.shared

    private init() {}

    #if DEBUG
    /// `--render-snapshots` only: sample cameras without a console connection.
    func setSnapshotCameras(_ cameras: [ProtectCamera]) {
        self.cameras = cameras
    }
    #endif

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
        let router = ConnectionRouter.shared
        let pin = settings.protectCertificateFingerprint
        // Away: 127.0.0.1:<forward>, never the direct address as a fallback (fail closed).
        let apiHost = router.apiHost(for: host)
        // With a tunnel configured the app may be away, where a foreign device can answer on the
        // console's address: no trust on first use, neither direct nor through the tunnel.
        if RouteDecision.requiresConfirmedPin(hasTunnel: TunnelStore.shared.hasConfiguration, pinned: pin) {
            client = nil
            cameras = []
            lastError = TunnelRouteError.certificateUnconfirmed.errorDescription
            return
        }
        guard let apiHost else {
            client = nil
            cameras = []
            lastError = TunnelRouteError.apiUnreachable.errorDescription
            return
        }
        // Through the tunnel the key only goes to a console whose certificate is already
        // pinned (confirmed at home or via re-trust); no trust on first use there.
        if router.isViaTunnel, pin?.isEmpty ?? true {
            client = nil
            cameras = []
            lastError = TunnelRouteError.pinRequired.errorDescription
            return
        }
        client = ProtectClient(
            // The pin below stays the console's, whichever address is dialed.
            host: apiHost,
            apiKey: settings.protectAPIKey,
            pinnedFingerprint: pin,
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
            prefetchAspectRatios()
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
        let cacheKey = "\(cameraId)#\(mapping.streamQuality.rawValue)"
        if let cached = streamCache[cacheKey] { return cached }
        do {
            let url = try await client.rtspURL(cameraId: cameraId, order: mapping.streamQuality.fallbackOrder)
            if let url, client === self.client { streamCache[cacheKey] = url }
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
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            aspectRatios[cameraId] = Double(rep.pixelsWide) / Double(rep.pixelsHigh)
        }
        return image
    }

    /// nil until a snapshot of the camera was seen.
    func aspectRatio(cameraId: String) -> Double? {
        aspectRatios[cameraId]
    }

    /// Cameras whose aspect-ratio snapshot is in flight: a refresh while it runs adds no second one.
    private var prefetching: Set<String> = []

    /// One snapshot per linked camera whose picture format is still unknown (once per launch).
    private func prefetchAspectRatios() {
        let missing = Set(settings.mappings.compactMap(\.protectCameraId))
            .filter { aspectRatios[$0] == nil && !prefetching.contains($0) }
        guard !missing.isEmpty else { return }
        prefetching.formUnion(missing)
        Task {
            for cameraId in missing {
                _ = await snapshot(cameraId: cameraId)
                prefetching.remove(cameraId)
            }
        }
    }
}
