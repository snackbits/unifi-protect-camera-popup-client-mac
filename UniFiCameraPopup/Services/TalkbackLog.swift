import Foundation

/// Diagnosis for talkback (not yet verified on real hardware): every step goes to the system
/// log and to ~/Library/Logs/UniFi Camera Popup/talkback.log (rotated at 512 KB).
/// Never logs the API key – only camera ids, the session answer and packet counts.
enum TalkbackLog {
    static let fileURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/UniFi Camera Popup/talkback.log")
    private static let queue = DispatchQueue(label: "com.snackbits.UniFiCameraPopup.talkback-log")
    private static let maxBytes = 512 * 1024

    static func write(_ message: String) {
        NSLog("%@", message)
        let line = "\(ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime, .withFractionalSeconds])) \(message)\n"
        queue.async {
            let manager = FileManager.default
            try? manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = (try? manager.attributesOfItem(atPath: fileURL.path))?[.size] as? Int, size > maxBytes {
                let old = fileURL.deletingPathExtension().appendingPathExtension("old.log")
                try? manager.removeItem(at: old)
                try? manager.moveItem(at: fileURL, to: old)
            }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: fileURL)
            }
        }
    }
}
