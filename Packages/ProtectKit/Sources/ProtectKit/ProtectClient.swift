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

public final class ProtectClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
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

    /// Reads the certificate fingerprint a console presents, without ever sending an API key.
    /// Used for the two-phase re-trust: the user confirms the fingerprint before any credential
    /// is sent over a connection pinned to it. The HTTP status is irrelevant (401 is expected).
    public static func probeFingerprint(host: String) async throws -> String {
        try await probeFingerprint(host: host, protocolClasses: nil)
    }

    static func probeFingerprint(host: String, protocolClasses: [AnyClass]?) async throws -> String {
        guard baseURL(for: host) != nil else { throw ProtectError.invalidHost }
        let box = FingerprintBox()
        let client = ProtectClient(
            host: host, apiKey: "", pinnedFingerprint: nil,
            onNewFingerprint: { box.set($0) }, protocolClasses: protocolClasses
        )
        defer { client.invalidate() }
        var failure: Error?
        do { _ = try await client.metaInfo() } catch { failure = error }
        if let fingerprint = box.value { return fingerprint }
        if case .unreachable? = failure as? ProtectError, let failure { throw failure }
        throw ProtectError.unreachable("kein Zertifikat erhalten")
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

    /// One spelling per console, so pins and host comparisons cannot be bypassed by
    /// writing the same address differently ("https://H/", "h:443", " h "):
    /// lowercased host, plus ":port" only for a non-default port. nil = not a valid host.
    public static func canonicalHost(_ raw: String) -> String? {
        guard let url = baseURL(for: raw),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = comps.host?.lowercased(), !host.isEmpty else { return nil }
        let name = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        guard let port = comps.port, port != 443 else { return name }
        return "\(name):\(port)"
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

    /// Current still image of a camera (JPEG). Used for thumbnails in settings and the menu panel.
    public func snapshot(cameraId: String) async throws -> Data {
        try await sendRaw("GET", "/v1/cameras/\(cameraId)/snapshot", body: nil, accept: "image/jpeg")
    }

    public func eventsWebSocket() -> URLSessionWebSocketTask {
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        comps.scheme = "wss"
        comps.path += "/v1/subscribe/events"
        var request = URLRequest(url: comps.url!)
        if !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY") }
        return session.webSocketTask(with: request)
    }

    // MARK: Transport

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await send("GET", path, body: nil)
    }

    private func send<T: Decodable>(_ method: String, _ path: String, body: Data?) async throws -> T {
        let data = try await sendRaw(method, path, body: body, accept: "application/json")
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw ProtectError.decoding }
    }

    private func sendRaw(_ method: String, _ path: String, body: Data?, accept: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(String(path.dropFirst())))
        request.httpMethod = method
        if !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY") }
        request.setValue(accept, forHTTPHeaderField: "Accept")
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
        case 200..<300: return data
        case 401, 403: throw ProtectError.unauthorized
        default: throw ProtectError.http(http.statusCode)
        }
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

    /// Redirects are refused: URLSession would copy the X-API-KEY header onto the new
    /// request, handing the key to whatever host the console (or an impostor) names.
    /// The 3xx response itself is returned and surfaces as `ProtectError.http`.
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
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

private final class FingerprintBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    var value: String? { lock.withLock { stored } }
    func set(_ fingerprint: String) { lock.withLock { stored = fingerprint } }
}
