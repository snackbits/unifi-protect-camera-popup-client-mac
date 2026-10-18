import Foundation
import ProtectKit

/// Runs the in-app WireGuard tunnel: start/stop, local forwards, liveness.
/// Only `ConnectionRouter` decides *when* the tunnel is needed.
///
/// Every `TunnelBridge` call runs on one serial queue (`bridge`): the Go side keeps a single
/// global "last error", so a failed forward and the read of its message must never interleave
/// with another call. Slow calls (start, rebind: DNS) are only ever awaited, never waited for
/// synchronously, so the main thread does not block on them.
@MainActor
final class TunnelController: ObservableObject {
    static let shared = TunnelController()
    /// Posted after all relayed connections were closed (tunnel back after an outage,
    /// wake from sleep). Owners of long-lived connections reconnect on it.
    static let connectionsResetNotification = Notification.Name("TunnelController.connectionsReset")

    @Published private(set) var state: TunnelRunState = .stopped
    @Published private(set) var lastHandshake: Date?

    /// Supplied by `ConnectionRouter` (NWPathMonitor), used for „Letzte Verbindung“.
    var networkKind: () -> NetworkKind = { .other }

    private let store = TunnelStore.shared
    private let bridge = DispatchQueue(label: "com.snackbits.UniFiCameraPopup.tunnel-bridge")
    private(set) var isStarted = false
    private var forwards: [ForwardTarget: Int] = [:]
    private var udpForwards: [ForwardTarget: Int] = [:]
    private var liveness = TunnelLiveness()
    /// The events WebSocket pings every 30 s: only while it is open does silence mean an outage.
    private var eventsSocketOpen = false
    /// When the events socket dropped while the tunnel ran (nil while it is open).
    private var socketClosedAt: Date?
    /// The socket closes ~40 s into an outage (ping timeout), before `TunnelLiveness` would
    /// notice. Closed at least this long and back again counts as an outage that ended.
    private let socketOutage: TimeInterval = 30
    private var poller: Task<Void, Never>?
    private var startTask: Task<Bool, Never>?
    /// Bumped by `start()` and `stop()`; a start that finishes after a stop is discarded.
    private var generation = 0

    private init() {}

    // MARK: Lifecycle

    /// Starts the tunnel from the stored config. True when the device is up; whether
    /// the peer answers shows in `state` (`.starting` until the first handshake).
    func start() async -> Bool {
        #if DEBUG
        // `--render-snapshots` never starts a tunnel.
        if SnapshotRenderer.isActive { return false }
        #endif
        if isStarted { return true }
        if let startTask { return await startTask.value }
        guard let config = store.configText else {
            state = .failed("Keine WireGuard-Konfiguration gespeichert.")
            return false
        }
        generation += 1
        let attempt = generation
        state = .starting
        let task = Task<Bool, Never> { @MainActor in
            let failure: String? = await self.onBridge {
                do {
                    try TunnelBridge.start(config)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }
            // Stopped meanwhile: `stop()` queued WgStop behind this start, so it is down again.
            guard attempt == self.generation else { return false }
            self.startTask = nil
            if let failure {
                NSLog("Tunnel: Start fehlgeschlagen – \(failure)")
                self.state = .failed(failure)
                return false
            }
            self.isStarted = true
            self.forwards = [:]
            self.udpForwards = [:]
            // Fresh per start: counters and stall timer of an earlier run mean nothing now.
            self.liveness = TunnelLiveness()
            self.lastHandshake = nil
            self.startPolling()
            NSLog("Tunnel: gestartet")
            return true
        }
        startTask = task
        return await task.value
    }

    /// Also clears a failed start: callers that want to keep its message for the status card
    /// (both paths failed) do not stop a tunnel that never came up.
    func stop() {
        generation += 1
        startTask = nil
        poller?.cancel()
        poller = nil
        // Always queued: runs after a start that is still in flight, and is a no-op otherwise.
        bridge.async { TunnelBridge.stop() }
        if isStarted { NSLog("Tunnel: gestoppt") }
        isStarted = false
        forwards = [:]
        udpForwards = [:]
        liveness = TunnelLiveness()
        socketClosedAt = nil
        state = .stopped
    }

    // MARK: Forwards

    /// Local TCP port on 127.0.0.1 for `target` if it already exists. Never calls into Go.
    func cachedLocalPort(for target: ForwardTarget) -> Int? {
        isStarted ? forwards[target] : nil
    }

    /// Local TCP port on 127.0.0.1 for `target`, created on first use. nil while stopped
    /// or when the tunnel refuses the target (outside AllowedIPs, host name without DNS).
    func localPort(for target: ForwardTarget) async -> Int? {
        guard isStarted else { return nil }
        if let port = forwards[target] { return port }
        let attempt = generation
        let result: Result<Int, TunnelBridge.Failure> = await onBridge {
            Self.result { try TunnelBridge.addForward(target) }
        }
        guard attempt == generation, isStarted else { return nil }
        switch result {
        case .success(let port):
            forwards[target] = port
            return port
        case .failure(let failure):
            NSLog("Tunnel: Weiterleitung \(target.host):\(target.port) – \(failure.message)")
            return nil
        }
    }

    /// Local UDP port on 127.0.0.1 that leads to `ip:port` (talkback). `ip` must be a
    /// literal inside AllowedIPs.
    func localUDPPort(ip: String, port: Int) async -> Int? {
        guard isStarted else { return nil }
        let target = ForwardTarget(host: ip, port: port)
        if let local = udpForwards[target] { return local }
        let attempt = generation
        let result: Result<Int, TunnelBridge.Failure> = await onBridge {
            Self.result { try TunnelBridge.addUDPForward(ip: ip, port: port) }
        }
        guard attempt == generation, isStarted else { return nil }
        switch result {
        case .success(let local):
            udpForwards[target] = local
            return local
        case .failure(let failure):
            NSLog("Tunnel: UDP-Weiterleitung \(ip):\(port) – \(failure.message)")
            return nil
        }
    }

    /// Checks a config with the Go parser (no tunnel needed, nothing is started).
    func parse(_ config: String) async -> TunnelParseResult {
        // Awaited, never waited for: the queue may be busy with a start resolving DNS.
        await onBridge { TunnelBridge.parse(config) }
    }

    /// Closes every relayed connection, then tells their owners to reconnect.
    func resetConnections(reason: String) {
        guard isStarted else { return }
        let attempt = generation
        Task { @MainActor in
            let closed = await self.onBridge { TunnelBridge.resetConnections() }
            guard attempt == self.generation else { return }
            NSLog("Tunnel: \(reason) – \(closed) Verbindung(en) neu aufbauen")
            NotificationCenter.default.post(name: Self.connectionsResetNotification, object: nil)
        }
    }

    /// New network: re-resolve the endpoint and rebind the UDP socket.
    /// TCP connections inside the tunnel survive this (WireGuard roams).
    func networkChanged() async {
        guard isStarted else { return }
        let failure: String? = await onBridge {
            do {
                try TunnelBridge.rebind()
                return nil
            } catch {
                return error.localizedDescription
            }
        }
        if let failure { NSLog("Tunnel: Rebind – \(failure)") }
    }

    /// Waits until a handshake completed, polling the status.
    func waitForHandshake(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, isStarted {
            if await onBridge({ TunnelBridge.status() }).lastHandshake != nil { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }

    // MARK: Liveness

    /// `ProtectEventService` status: open = connected (pings flow every 30 s).
    func eventsSocketChanged(open: Bool) {
        guard open != eventsSocketOpen else { return }
        eventsSocketOpen = open
        guard isStarted else {
            socketClosedAt = nil
            return
        }
        if !open {
            socketClosedAt = Date()
            // Not fed while the socket is closed, so a quiet tunnel is no outage. A detected
            // outage is kept: the next received byte is still the recovery.
            if !liveness.isDown { liveness = TunnelLiveness() }
            return
        }
        defer { socketClosedAt = nil }
        // A detected outage is ended by `sample()` (one reset on the next received byte);
        // a second reset here would only kill the socket that just reopened.
        guard !liveness.isDown else { return }
        // A quick reconnect (new client, route change) is no outage; a long one may have left
        // relayed streams stuck, so they are rebuilt once.
        if let closedAt = socketClosedAt, Date().timeIntervalSince(closedAt) >= socketOutage {
            resetConnections(reason: "Ereignis-Verbindung nach Ausfall zurück")
        }
    }

    private func startPolling() {
        poller?.cancel()
        poller = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.sample()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func sample() async {
        guard isStarted else { return }
        let attempt = generation
        let status = await onBridge { TunnelBridge.status() }
        guard attempt == generation, isStarted, status.up else { return }
        if let handshake = status.lastHandshake {
            lastHandshake = handshake
            if state == .starting { state = .up }
            if store.lastConnection.map({ handshake.timeIntervalSince($0.date) > 60 }) ?? true {
                store.recordConnection(at: handshake, via: networkKind())
            }
        }
        guard eventsSocketOpen || liveness.isDown else { return }
        switch liveness.observe(rxBytes: status.rxBytes, at: Date()) {
        case .wentDown:
            NSLog("Tunnel: keine Antwort mehr")
            state = .down
        case .recovered:
            state = .up
            socketClosedAt = nil  // this reset covers the socket's outage too
            resetConnections(reason: "Tunnel wieder da")
        case .none:
            break
        }
    }

    // MARK: Bridge queue

    private func onBridge<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            bridge.async { continuation.resume(returning: work()) }
        }
    }

    private nonisolated static func result(_ work: () throws -> Int) -> Result<Int, TunnelBridge.Failure> {
        do {
            return .success(try work())
        } catch let failure as TunnelBridge.Failure {
            return .failure(failure)
        } catch {
            return .failure(TunnelBridge.Failure(message: error.localizedDescription))
        }
    }
}
