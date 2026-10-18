import Foundation
import Security

public enum ProtectError: Error, Equatable, LocalizedError {
    case invalidHost
    case unauthorized
    case certificateChanged
    case http(Int)
    case unreachable(String)
    case decoding

    public var errorDescription: String? {
        switch self {
        case .invalidHost: return "Die Adresse der Konsole ist ungültig."
        case .unauthorized: return "Der API-Schlüssel wurde abgelehnt."
        case .certificateChanged: return "Das Zertifikat der Konsole hat sich geändert. Bitte die Verbindung neu bestätigen."
        case .http(let code): return "Die Konsole antwortete mit Fehler \(code)."
        case .unreachable(let detail): return "Die Konsole ist nicht erreichbar (\(detail))."
        case .decoding: return "Die Antwort der Konsole war unerwartet."
        }
    }
}

public final class ProtectClient: NSObject, URLSessionDelegate, @unchecked Sendable {
    public let baseURL: URL
    private let apiKey: String
    private let lock = NSLock()
    private var pinnedFingerprint: String?
    private var sawChangedCertificate = false
    private var isInvalidated = false
    private let onNewFingerprint: @Sendable (String) -> Void
    private var session: URLSession!

    public init(
        host: String,
        apiKey: String,
        pinnedFingerprint: String?,
        onNewFingerprint: @escaping @Sendable (String) -> Void,
        protocolClasses: [AnyClass]? = nil
    ) {
        self.baseURL = Self.baseURL(for: host) ?? URL(string: "https://invalid.invalid")!
        self.apiKey = apiKey
        self.pinnedFingerprint = pinnedFingerprint
        self.onNewFingerprint = onNewFingerprint
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        if let protocolClasses { config.protocolClasses = protocolClasses }
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    public static func baseURL(for host: String) -> URL? {
        var trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        guard var comps = URLComponents(string: trimmed), let h = comps.host, !h.isEmpty else { return nil }
        comps.scheme = "https"
        comps.path = "/proxy/protect/integration"
        comps.query = nil
        return comps.url
    }

    // MARK: API

    public func metaInfo() async throws -> ProtectMetaInfo {
        try await get("/v1/meta/info")
    }

    public func cameras() async throws -> [ProtectCamera] {
        try await get("/v1/cameras")
    }

    public func rtspURL(cameraId: String) async throws -> String? {
        let existing: RTSPSStreams = try await get("/v1/cameras/\(cameraId)/rtsps-stream")
        if let url = existing.preferred { return StreamURL.normalizedRTSP(url) }
        let created: RTSPSStreams = try await send(
            "POST", "/v1/cameras/\(cameraId)/rtsps-stream",
            body: Data(#"{"qualities":["high"]}"#.utf8)
        )
        return created.preferred.map(StreamURL.normalizedRTSP)
    }

    public func eventsWebSocket() -> URLSessionWebSocketTask {
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        comps.scheme = "wss"
        comps.path += "/v1/subscribe/events"
        var request = URLRequest(url: comps.url!)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        return session.webSocketTask(with: request)
    }

    // MARK: Transport

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await send("GET", path, body: nil)
    }

    private func send<T: Decodable>(_ method: String, _ path: String, body: Data?) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(String(path.dropFirst())))
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // Creating a task on an invalidated session raises an NSException, so fail early.
        if lock.withLock({ isInvalidated }) { throw ProtectError.unreachable("Verbindung beendet") }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if lock.withLock({ sawChangedCertificate }) { throw ProtectError.certificateChanged }
            throw ProtectError.unreachable((error as NSError).localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw ProtectError.decoding }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw ProtectError.unauthorized
        default: throw ProtectError.http(http.statusCode)
        }
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw ProtectError.decoding }
    }

    // MARK: Lifecycle

    /// Cancels in-flight requests and open WebSockets and releases the session.
    /// URLSession retains its delegate, so owners must call this when replacing or discarding the client.
    public func invalidate() {
        lock.withLock { isInvalidated = true }
        session.invalidateAndCancel()
    }

    // MARK: URLSessionDelegate (TOFU pinning)

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let (disposition, credential) = evaluate(trust: trust)
        completionHandler(disposition, credential)
    }

    /// Pin check for a presented server trust (trust on first use).
    func evaluate(trust: SecTrust) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else {
            return (.performDefaultHandling, nil)
        }
        let presented = CertificatePinning.fingerprint(of: SecCertificateCopyData(leaf) as Data)
        let decision = lock.withLock { () -> PinDecision in
            let d = CertificatePinning.decide(presented: presented, pinned: pinnedFingerprint)
            switch d {
            case .trustAndRemember(let fp): pinnedFingerprint = fp
            case .trust: break
            case .reject: sawChangedCertificate = true
            }
            return d
        }
        switch decision {
        case .trustAndRemember(let fp):
            onNewFingerprint(fp)
            return (.useCredential, URLCredential(trust: trust))
        case .trust:
            return (.useCredential, URLCredential(trust: trust))
        case .reject:
            return (.cancelAuthenticationChallenge, nil)
        }
    }
}
