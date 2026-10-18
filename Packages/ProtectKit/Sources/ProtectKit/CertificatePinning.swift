import CryptoKit
import Foundation

public enum PinDecision: Equatable {
    case trustAndRemember(String)
    case trust
    case reject
}

public enum CertificatePinning {
    public static func fingerprint(of der: Data) -> String {
        SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    /// Trust on first use; afterwards only the remembered certificate.
    public static func decide(presented: String, pinned: String?) -> PinDecision {
        guard let pinned else { return .trustAndRemember(presented) }
        return pinned == presented ? .trust : .reject
    }
}
