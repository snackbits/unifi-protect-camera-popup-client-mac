import Foundation

/// Best-effort detection of an active macOS Focus / Do Not Disturb mode.
///
/// macOS provides no public API to read the current Focus state, so this reads
/// the (undocumented) assertions database that the system writes when a Focus
/// mode is turned on. The location can change between macOS releases and may
/// require Full Disk Access. If the state cannot be determined we deliberately
/// return `false` so popups are never suppressed by accident.
enum DoNotDisturbChecker {
    private static let candidatePaths: [String] = {
        let home = NSHomeDirectory()
        return [
            "\(home)/Library/DoNotDisturb/DB/Assertions.json",
            "\(home)/Library/Group Containers/group.com.apple.donotdisturb/DoNotDisturb/DB/Assertions.json",
        ]
    }()

    static var isActive: Bool {
        for path in candidatePaths where FileManager.default.fileExists(atPath: path) {
            if let active = assertionActive(atPath: path) {
                return active
            }
        }
        return false
    }

    private static func assertionActive(atPath path: String) -> Bool? {
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        guard let entries = json["data"] as? [[String: Any]] else { return false }

        for entry in entries {
            if let records = entry["storeAssertionRecords"] as? [[String: Any]], !records.isEmpty {
                return true
            }
        }
        return false
    }
}
