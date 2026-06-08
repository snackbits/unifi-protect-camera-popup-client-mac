import Combine
import Foundation

@MainActor
final class WebSocketClient: ObservableObject {
    @Published private(set) var status: ConnectionStatus = .disconnected

    var onTrigger: ((TriggerEvent) -> Void)?

    private let settings: SettingsStore
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var isRunning = false

    init(settings: SettingsStore = .shared) {
        self.settings = settings
    }

    func start() {
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

    func reconnect() {
        stop()
        isRunning = true
        connect()
    }

    private func connect() {
        guard isRunning else { return }

        let urlString = settings.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = settings.appToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: urlString), !token.isEmpty else {
            status = .disconnected
            scheduleReconnect()
            return
        }

        status = .connecting

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        self.session = session
        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            await self?.listen()
        }

        reconnectAttempt = 0
        status = .connected
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
            await MainActor.run {
                self.handleDisconnect()
            }
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

        case "ping":
            sendPong()

        default:
            break
        }
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
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        status = .disconnected
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard isRunning else { return }

        reconnectTask?.cancel()
        let delay = min(pow(2.0, Double(reconnectAttempt)), 30.0)
        reconnectAttempt += 1

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run {
                self?.connect()
            }
        }
    }
}
