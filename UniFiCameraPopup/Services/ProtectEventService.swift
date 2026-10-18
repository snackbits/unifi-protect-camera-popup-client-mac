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
    private var dedup = EventDeduplicator()
    private var backoff = Backoff(base: 2, max: 60)

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
        startLoop()
    }

    func stop() {
        clientChange = nil
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
            do {
                // Protect may stay silent for a long time; a pong confirms the connection.
                try await ping(ws)
                markConnected()
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
            // A restarted loop owns `status` and `task` now.
            guard !Task.isCancelled else { return }
            ws.cancel(with: .goingAway, reason: nil)
            status = .disconnected
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

    private func ping(_ ws: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ws.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func handle(_ data: Data) {
        guard let trigger = EventMessage.parse(data), dedup.isNew(trigger.eventId) else { return }
        for mapping in settings.mappings(forProtectCamera: trigger.cameraId)
        where !mapping.triggers.isDisjoint(with: trigger.kinds) {
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
