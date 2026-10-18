import CryptoKit
import Foundation

/// SHA-256 of downloaded voices, read in 1 MiB pieces (models are up to 114 MB).
public enum FileChecksum {
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Size and hash both match (size first: cheap, catches truncated downloads).
    public static func matches(_ url: URL, _ file: VoiceFile) -> Bool {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber,
              size.int64Value == file.size else { return false }
        return (try? sha256(of: url)) == file.sha256.lowercased()
    }
}
