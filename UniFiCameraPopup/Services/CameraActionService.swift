import Foundation

/// Calls the webhook behind a popup action button (e.g. "Tür öffnen").
enum CameraActionService {
    static func trigger(_ action: CameraAction) async throws {
        guard let url = action.requestURL else {
            throw CameraActionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = action.method.rawValue
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let token = action.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CameraActionError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CameraActionError.httpStatus(http.statusCode)
        }
    }
}

enum CameraActionError: LocalizedError {
    case invalidURL
    case badResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Ungültige Webhook-URL."
        case .badResponse:
            return "Server antwortete unerwartet."
        case .httpStatus(let code):
            return "Server antwortete mit Status \(code)."
        }
    }
}
