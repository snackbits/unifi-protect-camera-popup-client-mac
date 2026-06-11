import AppKit
import Combine
import Foundation

@MainActor
final class WebSocketClient: NSObject, ObservableObject {
    @Published private(set) var status: ConnectionStatus = .disconnected

    var onTrigger: ((TriggerEvent) -> Void)?

    private let settings: SettingsStore
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var reconnectTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var livenessTask: Task<Void, Never>?
    private var isRunning = false
    private var lastServerPingAt: Date?
    private var handshakeOpenedAt: Date?
    private var wakeObserver: NSObjectProtocol?

    /// Set once the server reports a version mismatch. While set, the app no
    /// longer attempts to reconnect. Only an app restart clears this (new process).
    private var versionMismatch = false

    /// Fixed retry interval while disconnected (seconds).
    private let reconnectInterval: TimeInterval = 60

    /// Must exceed the server's heartbeat timeout (default 90 s).
    private let serverPingTimeout: TimeInterval = 100

    /// Time to wait for the first server ping after the WebSocket opens.
    private let handshakeConfirmTimeout: TimeInterval = 15

    init(settings: SettingsStore = .shared) {
        self.settings = settings
        super.init()
    }

    func start() {
        guard !versionMismatch else { return }
        isRunning = true
        observeSystemWake()
        connect()
    }

    func stop() {
        isRunning = false
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        reconnectTask?.cancel()
        receiveTask?.cancel()
        livenessTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        status = .disconnected
    }

    private func connect() {
        guard isRunning else { return }

        let token = AppConfig.appToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let installationId = settings.installationId

        guard let url = makeURL(installationId: installationId), !token.isEmpty else {
            status = .disconnected
            scheduleReconnect()
            return
        }

        status = .connecting

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        lastServerPingAt = nil
        handshakeOpenedAt = nil

        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            await self?.listen()
        }

        livenessTask?.cancel()
        livenessTask = Task { [weak self] in
            await self?.watchLiveness()
        }
    }

    private func makeURL(installationId: String) -> URL? {
        let base = AppConfig.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: base) else { return nil }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "uid", value: installationId))
        queryItems.append(URLQueryItem(name: "v", value: AppConfig.buildVersionId))
        components.queryItems = queryItems
        return components.url
    }

    private func listen() async {
        guard let task = webSocketTask else { return }

        do {
            while !Task.isCancelled {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    await handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleMessage(text)
                    }
                @unknown default:
                    break
                }
            }
        } catch {
            handleDisconnect()
        }
    }

    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "trigger":
            // Only process events addressed to this installation, so traffic
            // from other users never reaches this app.
            if let uid = json["uid"] as? String, uid != settings.installationId {
                return
            }

            let webhookId = json["webhookId"] as? String ?? ""
            let thumbnail = json["thumbnail"] as? String
            let alarmName = json["alarmName"] as? String
            let ts = json["ts"] as? TimeInterval ?? Date().timeIntervalSince1970 * 1000

            let event = TriggerEvent(
                webhookId: webhookId,
                thumbnail: thumbnail,
                alarmName: alarmName,
                timestamp: Date(timeIntervalSince1970: ts / 1000)
            )
            onTrigger?(event)

        case "version_mismatch":
            handleVersionMismatch()

        case "ping":
            lastServerPingAt = Date()
            if status != .connected {
                status = .connected
            }
            sendPong()

        default:
            break
        }
    }

    private func watchLiveness() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard isRunning, !versionMismatch else { return }

            if let lastServerPingAt {
                if Date().timeIntervalSince(lastServerPingAt) > serverPingTimeout {
                    NSLog("WebSocket server ping timeout – reconnecting")
                    forceReconnect()
                    return
                }
                continue
            }

            if let handshakeOpenedAt,
               Date().timeIntervalSince(handshakeOpenedAt) > handshakeConfirmTimeout {
                NSLog("WebSocket handshake not confirmed by server – reconnecting")
                forceReconnect()
                return
            }
        }
    }

    private func observeSystemWake() {
        guard wakeObserver == nil else { return }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleSystemWake()
            }
        }
    }

    private func handleSystemWake() {
        guard isRunning, !versionMismatch else { return }
        NSLog("System wake – reconnecting WebSocket")
        reconnectImmediately()
    }

    private func forceReconnect() {
        tearDownConnection()
        status = .disconnected
        scheduleReconnect()
    }

    private func reconnectImmediately() {
        tearDownConnection()
        connect()
    }

    private func tearDownConnection() {
        receiveTask?.cancel()
        livenessTask?.cancel()
        reconnectTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        lastServerPingAt = nil
        handshakeOpenedAt = nil
    }

    private func handleVersionMismatch() {
        versionMismatch = true
        isRunning = false
        reconnectTask?.cancel()
        receiveTask?.cancel()
        livenessTask?.cancel()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        status = .outdated
    }

    private func sendPong() {
        let payload = #"{"type":"pong","ts":\#(Int(Date().timeIntervalSince1970 * 1000))}"#
        webSocketTask?.send(.string(payload)) { error in
            if let error {
                NSLog("WebSocket pong error: \(error.localizedDescription)")
            }
        }
    }

    private func handleDisconnect() {
        // Keep the "outdated" state and never reconnect after a version mismatch.
        guard !versionMismatch else { return }

        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        lastServerPingAt = nil
        handshakeOpenedAt = nil
        if status != .disconnected {
            status = .disconnected
        }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard isRunning, !versionMismatch else { return }

        reconnectTask?.cancel()
        let interval = reconnectInterval
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            await MainActor.run {
                self?.connect()
            }
        }
    }
}

extension WebSocketClient: URLSessionWebSocketDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor in
            // Stay on "connecting" until the server sends a ping, which only
            // happens after the client is registered in the relay hub.
            if self.status != .outdated {
                self.handshakeOpenedAt = Date()
                self.status = .connecting
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor in
            self.handleDisconnect()
        }
    }
}
