import Foundation

/// Calls the webhook behind a popup action button (e.g. "Tür öffnen").
///
/// Redirects are never followed, at home or away: a webhook is one endpoint, and a 3xx could
/// downgrade https to http or send the Bearer token on to another host. The 3xx response is
/// the result (shown as its HTTP status).
enum CameraActionService {
    /// Own session: `URLSession.shared` would follow redirects. Ephemeral: no cookies, no cache.
    private static let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)

    /// Calls the webhook; returns the HTTP status (2xx) for the sheet's test result.
    @discardableResult
    static func trigger(_ action: CameraAction) async throws -> Int {
        guard let requested = action.requestURL else {
            throw CameraActionError.invalidURL
        }
        // Away: a LAN target (IP literal inside AllowedIPs) goes through a tunnel forward.
        guard let routed = await ConnectionRouter.shared.webhookURL(for: requested) else {
            throw CameraActionError.tunnelUnreachable
        }
        let url = routed.url

        var request = URLRequest(url: url)
        request.httpMethod = action.method.rawValue
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let token = action.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let response: URLResponse
        if let host = routed.tunneledHost {
            // TLS stays end to end; the certificate is checked against the original address.
            (_, response) = try await session.data(for: request, delegate: ForwardedTLSCheck(host: host))
        } else {
            (_, response) = try await session.data(for: request)
        }
        guard let http = response as? HTTPURLResponse else {
            throw CameraActionError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CameraActionError.httpStatus(http.statusCode)
        }
        return http.statusCode
    }
}

enum CameraActionError: LocalizedError {
    case invalidURL
    case badResponse
    case httpStatus(Int)
    case tunnelUnreachable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Ungültige Webhook-URL."
        case .badResponse:
            return "Server antwortete unerwartet."
        case .httpStatus(let code):
            return "Server antwortete mit Status \(code)."
        case .tunnelUnreachable:
            return TunnelRouteError.webhookUnreachable.errorDescription ?? ""
        }
    }
}

/// Refuses every redirect: the 3xx response itself is handed back to the caller.
private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Server trust for a webhook dialed on 127.0.0.1:<forward>: evaluated with the default
/// policy against the original host, so a forward changes nothing about TLS validation.
/// As the task's delegate it also answers redirects – refused, like `NoRedirects`.
private final class ForwardedTLSCheck: NSObject, URLSessionTaskDelegate {
    private let host: String

    init(host: String) {
        self.host = host
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        // Fail closed: a trust that keeps another policy is never accepted.
        guard SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString)) == errSecSuccess else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
