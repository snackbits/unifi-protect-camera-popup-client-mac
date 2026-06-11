import Foundation

/// Best-effort detection of an active macOS Focus / Do Not Disturb mode.
///
/// macOS provides no public API to read the current Focus state, so this reads
/// the (undocumented) assertions database that the system writes when a Focus
/// mode is turned on. That file lives in a TCC-protected directory, so the app
/// needs **Full Disk Access** to read it. Without that grant every read fails
/// with `Operation not permitted`, which we surface as `.permissionRequired`
/// instead of silently pretending no Focus is active.
///
/// Manually toggled Focus modes write an assertion record; scheduled
/// (time-based) modes do not, so we additionally evaluate the configured
/// time windows in `ModeConfigurations.json`.
enum DoNotDisturbChecker {
    enum FocusState {
        /// A Focus / Do Not Disturb mode is currently on.
        case active
        /// No Focus mode is on (or no Focus has ever been configured).
        case inactive
        /// The assertions file exists but we lack Full Disk Access to read it.
        case permissionRequired
    }

    /// Canonical locations used by macOS 12+ (incl. Sequoia / Tahoe).
    private static var dbDirectory: String {
        "\(NSHomeDirectory())/Library/DoNotDisturb/DB"
    }
    private static var assertionsPath: String { "\(dbDirectory)/Assertions.json" }
    private static var modeConfigurationsPath: String { "\(dbDirectory)/ModeConfigurations.json" }

    static var state: FocusState {
        do {
            // 1) A manually toggled Focus mode writes an assertion record.
            let assertions = try read(assertionsPath)
            if hasActiveAssertion(in: assertions) { return .active }
        } catch let error as NSError {
            if isPermissionError(error) { return .permissionRequired }
            if !isFileMissing(error) { return .inactive }
            // File missing → no Focus ever configured; nothing scheduled either.
            return .inactive
        }

        // 2) No manual assertion → a scheduled (time-based) Focus may be active.
        if let configs = try? read(modeConfigurationsPath),
           hasActiveScheduledMode(in: configs) {
            return .active
        }
        return .inactive
    }

    private static func read(_ path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path), options: .uncached)
    }

    /// `true` only when we positively know a Focus mode is active. When the
    /// state is unknown (no permission) this returns `false` so popups are
    /// never suppressed by accident.
    static var isActive: Bool { state == .active }

    /// `false` when reading the Focus database is blocked by missing
    /// Full Disk Access. Used to nudge the user toward granting it.
    static var hasFullDiskAccess: Bool { state != .permissionRequired }

    private static func hasActiveAssertion(in data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["data"] as? [[String: Any]] else {
            return false
        }
        for entry in entries {
            if let records = entry["storeAssertionRecords"] as? [[String: Any]], !records.isEmpty {
                return true
            }
        }
        return false
    }

    /// Checks `ModeConfigurations.json` for a Focus mode whose enabled,
    /// time-based schedule currently overlaps the local clock. Location- and
    /// app-based triggers cannot be evaluated and are ignored.
    private static func hasActiveScheduledMode(in data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["data"] as? [[String: Any]] else {
            return false
        }

        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let minutesNow = (now.hour ?? 0) * 60 + (now.minute ?? 0)

        for entry in entries {
            for config in modeConfigurations(in: entry) {
                guard let triggers = (config["triggers"] as? [String: Any])?["triggers"] as? [[String: Any]] else {
                    continue
                }
                for trigger in triggers where isTimeTriggerActive(trigger, minutesNow: minutesNow) {
                    return true
                }
            }
        }
        return false
    }

    /// `modeConfigurations` has appeared both as a keyed dictionary and as an
    /// array across macOS releases, so normalise to a list of config objects.
    private static func modeConfigurations(in entry: [String: Any]) -> [[String: Any]] {
        if let array = entry["modeConfigurations"] as? [[String: Any]] {
            return array
        }
        if let dict = entry["modeConfigurations"] as? [String: Any] {
            return dict.values.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    private static func isTimeTriggerActive(_ trigger: [String: Any], minutesNow: Int) -> Bool {
        // `enabledSetting == 2` marks an active time-period schedule.
        guard (trigger["enabledSetting"] as? Int) == 2,
              let startHour = trigger["timePeriodStartTimeHour"] as? Int,
              let startMinute = trigger["timePeriodStartTimeMinute"] as? Int,
              let endHour = trigger["timePeriodEndTimeHour"] as? Int,
              let endMinute = trigger["timePeriodEndTimeMinute"] as? Int else {
            return false
        }

        let start = startHour * 60 + startMinute
        let end = endHour * 60 + endMinute
        if start == end { return false }
        if start < end {
            return minutesNow >= start && minutesNow < end
        }
        // Window wraps across midnight.
        return minutesNow >= start || minutesNow < end
    }

    private static func isFileMissing(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoSuchFileError {
            return true
        }
        return isPosix(error, ENOENT)
    }

    private static func isPermissionError(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain {
            if error.code == NSFileReadNoPermissionError { return true }
            if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError,
               isPosix(underlying, EPERM) || isPosix(underlying, EACCES) {
                return true
            }
        }
        return isPosix(error, EPERM) || isPosix(error, EACCES)
    }

    private static func isPosix(_ error: NSError, _ code: Int32) -> Bool {
        error.domain == NSPOSIXErrorDomain && error.code == Int(code)
    }
}
