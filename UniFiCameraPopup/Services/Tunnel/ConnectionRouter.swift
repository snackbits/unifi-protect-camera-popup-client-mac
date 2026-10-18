import AppCore
import AppKit
import Foundation
import Network
import ProtectKit

/// Decides whether the app reaches the console directly or through the in-app
/// tunnel, and maps API host, stream, webhook and talkback addresses accordingly.
///
/// Automatic mode: a short TLS probe of the configured console address. Only an
/// answer with the pinned certificate counts as "at home" – a foreign router on
/// the same address (192.168.1.1 in a hotel) does not. A probe result only switches
/// the route once a second one agrees (`RouteHysteresis`).
///
/// Fail closed: while the route is the tunnel, an address that cannot be mapped onto a
/// forward is never replaced by the direct one – the caller shows an error instead.
@MainActor
final class ConnectionRouter: ObservableObject {
    static let shared = ConnectionRouter()
    /// Posted after the route changed; `ProtectSession` is already reconnected then.
    static let routeDidChangeNotification = Notification.Name("ConnectionRouter.routeDidChange")

    @Published private(set) var route: ProtectRoute = .direct
    @Published private(set) var isTesting = false
    @Published private(set) var testOutcome: TunnelTestOutcome?
    /// Set while neither the direct path nor the tunnel reaches the console.
    @Published private(set) var problem: String?

    private let settings = SettingsStore.shared
    private let store = TunnelStore.shared
    private let tunnel = TunnelController.shared
    private let pathMonitor = NWPathMonitor()
    private var networkKind: NetworkKind = .other
    private var lastPathSignature: String?
    private var pending: Task<Void, Never>?
    private var recheck: Task<Void, Never>?
    private var evaluatedHost: String?
    private var lastFailureEvaluation = Date.distantPast
    private var wakeObserver: NSObjectProtocol?
    private var started = false
    private var hysteresis = RouteHysteresis(required: 2)
    /// Both paths failed: retry after 30 s, 60 s, … at most every 5 minutes.
    private var failureBackoff = Backoff(base: 30, max: 300)
    /// Delay of the second probe that confirms a route change.
    private let confirmDelay: TimeInterval = 3

    private init() {}

    func start() {
        #if DEBUG
        // `--render-snapshots`: no probe, no tunnel, nothing written.
        if SnapshotRenderer.isActive { return }
        #endif
        guard !started else { return }
        started = true
        tunnel.networkKind = { [weak self] in self?.networkKind ?? .other }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let kind = Self.kind(of: path)
            let signature = "\(path.status)|\(path.availableInterfaces.map(\.name).joined(separator: ","))|\(path.isExpensive)"
            Task { @MainActor in self?.pathChanged(kind: kind, signature: signature) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "ConnectionRouter.path"))
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.tunnel.resetConnections(reason: "Ruhezustand beendet")
                self?.scheduleEvaluation(reason: "Aufwachen", delay: 2)
            }
        }
        scheduleEvaluation(reason: "Start", delay: 0)
    }

    // MARK: Mapping

    /// The host `ProtectClient` connects to for the configured console. Uses only an existing
    /// forward (no call into the tunnel); nil while on the tunnel without one – never the
    /// direct address. A missing forward is created by the evaluation, which reconnects.
    func apiHost(for consoleHost: String) -> String? {
        if consoleHost == settings.protectHost, consoleHost != evaluatedHost {
            scheduleEvaluation(reason: "Konsole geändert", delay: 0)
        }
        guard route == .tunnel else { return consoleHost }
        guard let target = ForwardURL.apiTarget(consoleHost: consoleHost),
              let port = tunnel.cachedLocalPort(for: target) else { return nil }
        return ForwardURL.localHost(port: port)
    }

    /// Like `apiHost(for:)`, but creates the forward when needed (set-up and re-trust checks,
    /// also for an address other than the configured console). nil = not reachable now.
    func resolveAPIHost(for consoleHost: String) async -> String? {
        guard route == .tunnel else { return consoleHost }
        guard let target = ForwardURL.apiTarget(consoleHost: consoleHost),
              let port = await tunnel.localPort(for: target), route == .tunnel else { return nil }
        return ForwardURL.localHost(port: port)
    }

    var isViaTunnel: Bool { route == .tunnel }

    /// The URL VLC opens for a stream URL from Protect (or a manual one). nil while on the
    /// tunnel and the stream cannot go through it (rtsps, host outside AllowedIPs …).
    func playableStreamURL(_ original: String) async -> String? {
        guard route == .tunnel else { return original }
        guard let target = ForwardURL.streamTarget(original),
              let port = await tunnel.localPort(for: target), route == .tunnel,
              let local = ForwardURL.rewrite(original, localPort: port) else {
            NSLog("VLC: Stream unterwegs nicht über den Tunnel erreichbar")
            return nil
        }
        return local
    }

    /// Where a webhook call goes: through a forward while on the tunnel when the URL's host is
    /// an IP literal inside AllowedIPs, else unchanged. `tunneledHost` is the original host
    /// (TLS is verified against it). nil = refused: away, a private address outside AllowedIPs
    /// (would hit a device of the foreign network), or the forward failed.
    func webhookURL(for url: URL) async -> (url: URL, tunneledHost: String?)? {
        let target: ForwardTarget
        switch TunnelPath.webhook(url, route: route, allowedIPs: store.summary?.allowedIPs ?? []) {
        case .direct: return (url, nil)
        case .refuse: return nil
        case .forward(let forward): target = forward
        }
        guard let port = await tunnel.localPort(for: target), route == .tunnel,
              let local = TunnelPath.rewrite(url, localPort: port) else { return nil }
        return (local, target.host)
    }

    /// Where talkback audio goes: the camera directly at home, a local UDP forward away.
    func talkbackTarget(_ target: TalkbackTarget) async throws -> TalkbackTarget {
        let allowed = store.summary?.allowedIPs ?? []
        switch TunnelPath.talkback(host: target.host, port: Int(target.port), route: route, allowedIPs: allowed) {
        case .direct:
            return target
        case .notRouted:
            throw TunnelRouteError.talkbackNotRouted
        case .forward(let ip, let port):
            guard let local = await tunnel.localUDPPort(ip: ip, port: port), route == .tunnel,
                  let localPort = UInt16(exactly: local) else {
                throw TalkbackError.network("Weiterleitung durch den Tunnel fehlgeschlagen")
            }
            return TalkbackTarget(host: "127.0.0.1", port: localPort, codec: target.codec, sampleRate: target.sampleRate)
        }
    }

    // MARK: Triggers

    /// The events socket dropped. Rate-limited: the console may simply be rebooting.
    /// Ignored while both paths failed: the backoff retry is already scheduled and must not
    /// be replaced by a sooner one (network change and wake reset it instead).
    func noteConnectionFailure() {
        guard started, problem == nil, Date().timeIntervalSince(lastFailureEvaluation) > 30 else { return }
        lastFailureEvaluation = Date()
        scheduleEvaluation(reason: "Verbindung verloren", delay: 0)
    }

    /// Tunnel imported, replaced or removed, or „Tunnel verwenden“ changed.
    func configurationChanged() {
        hysteresis.reset()
        failureBackoff.reset()
        scheduleEvaluation(reason: "Einstellung geändert", delay: 0)
    }

    /// Imports a dropped or picked file and re-evaluates the route on success.
    func importTunnel(data: Data, fileName: String) async -> Result<TunnelImporter.Outcome, TunnelImporter.Failure> {
        let result = await TunnelImporter.importData(data, fileName: fileName)
        if case .success = result { tunnel.stop(); configurationChanged() }
        return result
    }

    /// Imports pasted text and re-evaluates the route on success.
    func importTunnel(text: String) async -> Result<TunnelImporter.Outcome, TunnelImporter.Failure> {
        let result = await TunnelImporter.importData(Data(text.utf8), fileName: TunnelImporter.pastedFileName)
        if case .success = result { tunnel.stop(); configurationChanged() }
        return result
    }

    func removeTunnel() {
        store.remove()
        testOutcome = nil
        configurationChanged()
    }

    /// „Jetzt testen“: tunnel up, handshake, console answers with the pinned certificate.
    /// Probes only – the API key is never sent.
    func testNow() async {
        guard !isTesting else { return }
        isTesting = true
        testOutcome = nil
        defer {
            isTesting = false
            if route == .direct { tunnel.stop() }
        }
        guard let target = ForwardURL.apiTarget(consoleHost: settings.protectHost) else {
            testOutcome = .noConsole
            return
        }
        guard await tunnel.start() else {
            if case .failed(let reason) = tunnel.state { testOutcome = .startFailed(reason) }
            else { testOutcome = .startFailed("unbekannter Fehler") }
            return
        }
        guard await tunnel.waitForHandshake(timeout: 10) else {
            testOutcome = .noHandshake(endpoint: store.summary?.endpoint ?? "der Gegenstelle")
            return
        }
        guard let port = await tunnel.localPort(for: target) else {
            testOutcome = .consoleSilent(host: target.host)
            return
        }
        do {
            let fingerprint = try await ProtectClient.probeFingerprint(host: ForwardURL.localHost(port: port), timeout: 5)
            switch DirectReachability.from(presentedFingerprint: fingerprint, pinned: settings.protectCertificateFingerprint) {
            case .console: testOutcome = .ok
            case .otherDevice, .unreachable: testOutcome = .otherDevice
            }
        } catch {
            testOutcome = .consoleSilent(host: target.host)
        }
    }

    // MARK: Evaluation

    private nonisolated static func kind(of path: NWPath) -> NetworkKind {
        // An iPhone hotspot is Wi-Fi but "expensive": show it as Mobilfunk.
        if path.usesInterfaceType(.cellular) || path.isExpensive { return .cellular }
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.wiredEthernet) { return .ethernet }
        return .other
    }

    private func pathChanged(kind: NetworkKind, signature: String) {
        networkKind = kind
        guard signature != lastPathSignature else { return }
        let first = lastPathSignature == nil
        lastPathSignature = signature
        guard !first else { return }  // start() evaluates already
        Task { await tunnel.networkChanged() }
        // A new network is a fresh start for the route: no half-confirmed candidate, no backoff.
        hysteresis.reset()
        failureBackoff.reset()
        // Give DHCP and DNS a moment before probing the console.
        scheduleEvaluation(reason: "Netzwerkwechsel", delay: 2)
    }

    private func scheduleEvaluation(reason: String, delay: TimeInterval) {
        guard started else { return }
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            await self?.evaluate(reason: reason)
        }
    }

    private func evaluate(reason: String) async {
        let consoleHost = settings.protectHost
        evaluatedHost = consoleHost
        guard settings.isProtectConfigured else {
            hysteresis.reset()
            await apply(.direct)
            return
        }
        let mode = store.mode
        let hasTunnel = store.hasConfiguration
        let probed = RouteDecision.needsProbe(mode: mode, hasTunnel: hasTunnel)
        var direct = DirectReachability.console
        if probed {
            // No API key: only the certificate is read.
            let fingerprint = try? await ProtectClient.probeFingerprint(host: consoleHost, timeout: 3)
            direct = DirectReachability.from(presentedFingerprint: fingerprint,
                                             pinned: settings.protectCertificateFingerprint)
        }
        // A newer evaluation or another console replaced this one meanwhile.
        guard !Task.isCancelled, consoleHost == settings.protectHost else { return }
        let wanted = RouteDecision.decide(mode: mode, hasTunnel: hasTunnel, direct: direct)
        NSLog("Route (\(reason)): \(wanted), direkt: \(direct)")
        // Mode „Immer“/„Nie“ or no tunnel: nothing to confirm.
        guard probed else {
            hysteresis.reset()
            await apply(wanted)
            return
        }
        if wanted == route {
            hysteresis.reset()
            await apply(wanted)  // keeps tunnel and forward healthy, re-arms the recheck
            return
        }
        if let confirmed = hysteresis.feed(wanted, current: route) {
            await apply(confirmed)
        } else {
            NSLog("Route: \(wanted) erst nach zweiter Prüfung")
            scheduleEvaluation(reason: "Bestätigung", delay: confirmDelay)
        }
    }

    private func apply(_ wanted: ProtectRoute) async {
        guard wanted == .tunnel else {
            problem = nil
            failureBackoff.reset()
            if route != .direct { setRoute(.direct) }
            if !isTesting { tunnel.stop() }
            scheduleRecheck()
            return
        }
        let wasRunning = tunnel.isStarted
        guard await tunnel.start() else {
            guard !Task.isCancelled else { return }
            let reason: String
            if case .failed(let message) = tunnel.state { reason = message } else { reason = "Tunnel startet nicht" }
            bothPathsFailed(reason)
            return
        }
        guard !Task.isCancelled else { return }
        // The API forward first: `ProtectSession.reconnect()` only uses existing forwards.
        let consoleHost = settings.protectHost
        guard let target = ForwardURL.apiTarget(consoleHost: consoleHost) else {
            bothPathsFailed("ungültige Konsolenadresse")
            return
        }
        let hadForward = tunnel.cachedLocalPort(for: target) != nil
        guard await tunnel.localPort(for: target) != nil else {
            guard !Task.isCancelled else { return }
            bothPathsFailed("Konsole \(target.host) ist über den Tunnel nicht erreichbar")
            return
        }
        guard !Task.isCancelled, consoleHost == settings.protectHost else { return }
        problem = nil
        failureBackoff.reset()
        // A (re)started tunnel or a new forward means new local ports: the client must reconnect.
        if route != .tunnel || !wasRunning || !hadForward { setRoute(.tunnel) }
        scheduleRecheck()
    }

    /// Neither path reaches the console: back to the direct route (the pin keeps the key from
    /// any other device), tunnel down, and a retry with growing pauses instead of a tight loop.
    private func bothPathsFailed(_ reason: String) {
        let delay = failureBackoff.next()
        problem = "Konsole weder direkt noch über den Tunnel erreichbar (\(reason))."
        NSLog("Route: kein Weg zur Konsole – \(reason); neuer Versuch in \(Int(delay)) s")
        hysteresis.reset()
        recheck?.cancel()
        recheck = nil
        // A start that failed keeps `.failed(reason)` for the status card.
        if !isTesting, tunnel.isStarted { tunnel.stop() }
        if route != .direct { setRoute(.direct) }
        scheduleEvaluation(reason: "Neuer Versuch", delay: delay)
    }

    /// On the tunnel in automatic mode, look for the console directly every 5 minutes:
    /// a short console outage at home must not leave the app on the tunnel for good.
    private func scheduleRecheck() {
        recheck?.cancel()
        recheck = nil
        guard route == .tunnel, store.mode == .automatic else { return }
        recheck = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000_000)
            guard !Task.isCancelled else { return }
            self?.scheduleEvaluation(reason: "Regelmäßige Prüfung", delay: 0)
        }
    }

    private func setRoute(_ new: ProtectRoute) {
        route = new
        NSLog("Route jetzt: \(new == .tunnel ? "Tunnel" : "direkt")")
        ProtectSession.shared.reconnect()
        NotificationCenter.default.post(name: Self.routeDidChangeNotification, object: nil)
    }
}

/// Why something cannot go through the tunnel. Texts are shown to the user.
enum TunnelRouteError: LocalizedError, Equatable {
    case talkbackNotRouted
    case apiUnreachable
    case streamUnreachable
    case webhookUnreachable
    case pinRequired

    var errorDescription: String? {
        switch self {
        case .talkbackNotRouted: return TunnelText.talkbackNotRouted
        case .apiUnreachable: return "Die Konsole ist über den Tunnel gerade nicht erreichbar."
        case .streamUnreachable: return "Livebild unterwegs nicht erreichbar."
        case .webhookUnreachable: return TunnelText.webhookNotRouted
        case .pinRequired: return "Unterwegs verbindet sich die App erst, wenn das Zertifikat deiner Konsole bestätigt ist."
        }
    }
}
