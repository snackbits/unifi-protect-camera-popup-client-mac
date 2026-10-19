import Foundation

/// German UI strings built from data, kept here so they are testable.
public enum DisplayText {
    private static let locale = Locale(identifier: "de_DE")

    private static func formatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// "10:41"
    public static func time(_ date: Date, timeZone: TimeZone = .current) -> String {
        formatter("HH:mm", timeZone).string(from: date)
    }

    /// "10:41:07"
    public static func timeWithSeconds(_ date: Date, timeZone: TimeZone = .current) -> String {
        formatter("HH:mm:ss", timeZone).string(from: date)
    }

    /// Popup chip: "Klingel · Haustür · 10:41"; without a kind "Haustür · 10:41";
    /// without a name "Kamera · 10:41". `seconds`: the live clock, "… · 10:41:07".
    public static func popupChip(
        kind: String?, camera: String, date: Date, seconds: Bool = false, timeZone: TimeZone = .current
    ) -> String {
        let name = camera.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKind = kind?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [
            trimmedKind?.isEmpty == false ? trimmedKind : nil,
            name.isEmpty ? "Kamera" : name,
            seconds ? timeWithSeconds(date, timeZone: timeZone) : time(date, timeZone: timeZone),
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    /// Menu panel event time: "10:12" today, "gestern", otherwise "12.10.".
    public static func shortTime(_ date: Date, now: Date, timeZone: TimeZone = .current) -> String {
        let calendar = calendar(timeZone)
        if calendar.isDate(date, inSameDayAs: now) { return time(date, timeZone: timeZone) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "gestern"
        }
        return formatter("dd.MM.", timeZone).string(from: date)
    }

    /// "Zuletzt ausgelöst": "heute, 10:12" · "gestern, 18:22" · "12.10., 09:30".
    public static func dayAndTime(_ date: Date, now: Date, timeZone: TimeZone = .current) -> String {
        let calendar = calendar(timeZone)
        let clock = time(date, timeZone: timeZone)
        if calendar.isDate(date, inSameDayAs: now) { return "heute, \(clock)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "gestern, \(clock)"
        }
        return "\(formatter("dd.MM.", timeZone).string(from: date)), \(clock)"
    }

    /// Mute end: "bis 10:56" · "bis morgen, 09:00" · "bis 20.10., 09:00".
    public static func until(_ date: Date, now: Date, timeZone: TimeZone = .current) -> String {
        let calendar = calendar(timeZone)
        let clock = time(date, timeZone: timeZone)
        if calendar.isDate(date, inSameDayAs: now) { return "bis \(clock)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "bis morgen, \(clock)"
        }
        return "bis \(formatter("dd.MM.", timeZone).string(from: date)), \(clock)"
    }

    /// Second line of a camera in the Kameras sidebar.
    public static func cameraState(
        triggerLabels: [String],
        webhook: Bool,
        mutedUntil: Date?,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String {
        if let mutedUntil { return "stumm " + until(mutedUntil, now: now, timeZone: timeZone) }
        var parts = triggerLabels
        if webhook { parts.append("Webhook") }
        return parts.isEmpty ? "aus" : parts.joined(separator: ", ")
    }

    /// Action rows show the address without scheme.
    public static func actionAddress(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        for scheme in ["https://", "http://"] where trimmed.lowercased().hasPrefix(scheme) {
            return String(trimmed.dropFirst(scheme.count))
        }
        return trimmed
    }
}

// MARK: - Phase 5

extension DisplayText {
    /// Menu panel: "Version 1.2.0 (29)".
    public static func version(short: String, build: Int) -> String {
        "Version \(short) (\(build))"
    }

    /// Menu panel update button: "Update auf 1.3.0 installieren"; same marketing version
    /// (newer build only) or none: "Update auf 1.2.0 (30) installieren".
    public static func updateButton(targetShort: String?, targetBuild: Int, currentShort: String) -> String {
        let short = (targetShort ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if short.isEmpty || short == currentShort {
            return "Update auf \(currentShort) (\(targetBuild)) installieren"
        }
        return "Update auf \(short) installieren"
    }

    /// Button row in Kameras: address without scheme, "Ton „Gong“" or "ha.local/x + Ton".
    public static func actionTarget(url: String, soundName: String?) -> String {
        let address = actionAddress(url)
        switch (address.isEmpty, soundName) {
        case (false, nil): return address
        case (false, .some): return "\(address) + Ton"
        case (true, let name?): return "Ton „\(name)“"
        case (true, nil): return ""
        }
    }
}
