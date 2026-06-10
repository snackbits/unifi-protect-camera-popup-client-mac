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
    private var isRunning = false

    /// Set once the server reports a version mismatch. While set, the app no
    /// longer attempts to reconnect. Only an app restart clears this (new process).
    private var versionMismatch = false

    /// Fixed retry interval while disconnected (seconds).
    private let reconnectInterval: TimeInterval = 60

    init(settings: SettingsStore = .shared) {
        self.settings = settings
        super.init()
    }

    func start() {
        guard !versionMismatch else { return }
        isRunning = true
        connect()
    }

    func stop() {
        isRunning = false
        reconnectTask?.cancel()
        receiveTask?.cancel()
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
        let appKey = settings.appKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = makeURL(installationId: installationId, appKey: appKey), !token.isEmpty else {
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

        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            await self?.listen()
        }
    }

    private func makeURL(installationId: String, appKey: String) -> URL? {
        let base = AppConfig.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: base) else { return nil }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "uid", value: installationId))
        queryItems.append(URLQueryItem(name: "v", value: AppConfig.buildVersionId))
        if !appKey.isEmpty {
            queryItems.append(URLQueryItem(name: "key", value: appKey))
        }
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
                    handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleMessage(text)
                    }
                @unknown default:
                    break
                }
            }
        } catch {
            handleDisconnect()
        }
    }

    private func handleMessage(_ text: String) {
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
            sendPong()

        default:
            break
        }
    }

    private func handleVersionMismatch() {
        versionMismatch = true
        isRunning = false
        reconnectTask?.cancel()
        receiveTask?.cancel()
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
            self.status = .connected
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
