import Foundation

public enum StreamURL {
    /// rtsps:// → rtsp://, :7441 → :7447, removes `enableSrtp`. Idempotent.
    public static func normalizedRTSP(_ url: String) -> String {
        var result = url
        if let range = result.range(of: "rtsps://", options: .caseInsensitive) {
            result.replaceSubrange(range, with: "rtsp://")
        }
        result = result.replacingOccurrences(of: ":7441", with: ":7447")
        result = result.replacingOccurrences(
            of: "[?&]enableSrtp(=[^&]*)?",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        if !result.contains("?"), let amp = result.firstIndex(of: "&") {
            result.replaceSubrange(amp...amp, with: "?")
        }
        return result
    }
}
