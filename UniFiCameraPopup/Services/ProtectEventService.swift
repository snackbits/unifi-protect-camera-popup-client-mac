import AppKit
import Combine
import Foundation
import ProtectKit

/// Listens to /v1/subscribe/events and turns matching Protect events into popups.
@MainActor
final class ProtectEventService: ObservableObject {
    @Published private(set) var status: ConnectionStatus = .disconnected
    var onTrigger: ((TriggerEvent) -> Void)?

    private let settings = SettingsStore.shared
    private var task: URLSessionWebSocketTask?
    private var loop: Task<Void, Never>?
    private var clientChange: AnyCancellable?
    private var wakeObserver: NSObjectProtocol?
    private var tunnelResetObserver: NSObjectProtocol?
    /// Follows each event from `add` through its updates: smart-detect kinds may only arrive later.
    private var tracker = EventTracker()
    private var backoff = Backoff(base: 2, max: 60)

    /// Keepalive interval while connected; a dead socket is otherwise never noticed.
    private let pingInterval: UInt64 = 30_000_000_000
    /// A ping without a pong in this time cancels the socket and triggers a reconnect.
    private let pongTimeout: UInt64 = 10_000_000_000
    func start() {
        stop()
        // `ProtectSession.reconnect()` invalidates the old client and publishes a new one.
        // Restarting the loop drops the old socket and connects with the new client right
        // away instead of waiting out a backoff delay. `@Published` emits in `willSet`, so
        // hop once to read the new value.
        clientChange = ProtectSession.shared.$client
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.restartLoop() }
            }
        // Sockets do not survive sleep reliably; reconnect right away on wake.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                NSLog("System wake – reconnecting Protect events")
                self?.restartLoop()
            }
        }
        // After a tunnel outage the old socket may hang forever: reconnect at once.
        tunnelResetObserver = NotificationCenter.default.addObserver(
            forName: TunnelController.connectionsResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.restartLoop() }
        }
        startLoop()
    }

    func stop() {
        clientChange = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let tunnelResetObserver {
            NotificationCenter.default.removeObserver(tunnelResetObserver)
            self.tunnelResetObserver = nil
        }
        stopLoop()
        status = .disconnected
    }

    private func startLoop() {
        backoff.reset()
        loop = Task { [weak self] in await self?.run() }
    }

    private func stopLoop() {
        loop?.cancel()
        loop = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func restartLoop() {
        guard clientChange != nil else { return }  // stopped meanwhile
        stopLoop()
        startLoop()
    }

    private func run() async {
        while !Task.isCancelled {
            // Read the current client and open the socket without a suspension point in
            // between, so an invalidated (replaced) client is never asked for a socket.
            guard let client = ProtectSession.shared.client else {
                status = .disconnected
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                continue
            }
            status = .connecting
            let ws = client.eventsWebSocket()
            task = ws
            ws.resume()
            var heartbeat: Task<Void, Never>?
            do {
                // Protect may stay silent for a long time; a pong confirms the connection.
                try await ping(ws)
                try Task.checkCancellation()  // superseded loops never touch status
                markConnected()
                heartbeat = keepAlive(ws)
                while !Task.isCancelled {
                    let message = try await ws.receive()
                    guard !Task.isCancelled else { break }
                    markConnected()
                    let data: Data
                    switch message {
                    case .string(let text): data = Data(text.utf8)
                    case .data(let d): data = d
                    @unknown default: continue
                    }
                    handle(data)
                }
            } catch {
                NSLog("Protect events websocket closed: \(error.localizedDescription)")
            }
            heartbeat?.cancel()
            // A restarted loop owns `status` and `task` now.
            guard !Task.isCancelled else { return }
            ws.cancel(with: .goingAway, reason: nil)
            status = .disconnected
            // Maybe the Mac left home (or came back): let the router check the route.
            ConnectionRouter.shared.noteConnectionFailure()
            let delay = backoff.next()
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    private func markConnected() {
        if status != .connected {
            status = .connected
            backoff.reset()
        }
    }

    /// Pings every `pingInterval`. A failed or unanswered ping cancels the socket, so
    /// `receive()` throws and the loop's backoff/reconnect path runs. Never touches `status`.
    private func keepAlive(_ ws: URLSessionWebSocketTask) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self?.pingInterval ?? 0)
                guard !Task.isCancelled, let self else { return }
                do {
                    try await self.ping(ws)
                } catch {
                    NSLog("Protect events ping failed: \(error.localizedDescription)")
                    ws.cancel(with: .goingAway, reason: nil)
                    return
                }
            }
        }
    }

    /// Sends a ping and waits for the pong. After `pongTimeout` the socket is cancelled
    /// and `PongTimeout` is thrown.
    private func ping(_ ws: URLSessionWebSocketTask) async throws {
        let wait = PongWait()
        let timeout = pongTimeout
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            wait.continuation = continuation
            wait.timer = Task { @MainActor in
                try? await Task.sleep(nanoseconds: timeout)
                guard !Task.isCancelled, wait.continuation != nil else { return }
                ws.cancel(with: .goingAway, reason: nil)
                wait.finish(PongTimeout())
            }
            ws.sendPing { error in
                Task { @MainActor in wait.finish(error) }
            }
        }
    }

    private func handle(_ data: Data) {
        // Only kinds this event has not reported before (an update can add „Fahrzeug“ to „Person“).
        guard let tracked = tracker.ingest(data) else { return }
        let trigger = tracked.trigger
        // Kameras › Ereignisse: independent of popups, mutes and Focus.
        EventRuleService.shared.handle(trigger)
        // A popup opens the first time the event matches the camera's triggers, as before.
        for mapping in settings.mappings(forProtectCamera: trigger.cameraId)
        where !mapping.triggers.isDisjoint(with: trigger.kinds) && mapping.triggers.isDisjoint(with: tracked.previousKinds) {
            let label = TriggerKind.ordered.first { trigger.kinds.contains($0) && mapping.triggers.contains($0) }?.label
            onTrigger?(TriggerEvent(
                webhookId: mapping.webhookId,
                thumbnail: nil,
                alarmName: [label, mapping.label].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                timestamp: trigger.start,
                mappingId: mapping.entryId,
                kinds: trigger.kinds
            ))
        }
    }
}

private struct PongTimeout: LocalizedError {
    var errorDescription: String? { "Keine Antwort auf Ping" }
}

/// Resumes a pong wait exactly once (pong, error or timeout, whichever comes first).
@MainActor
private final class PongWait {
    var continuation: CheckedContinuation<Void, Error>?
    var timer: Task<Void, Never>?

    func finish(_ error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        timer?.cancel()
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
