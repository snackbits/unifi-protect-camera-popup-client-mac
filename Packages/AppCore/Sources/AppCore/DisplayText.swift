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

    /// Popup chip: "Klingel · Haustür · 10:41"; without a kind "Haustür · 10:41";
    /// without a name "Kamera · 10:41".
    public static func popupChip(kind: String?, camera: String, date: Date, timeZone: TimeZone = .current) -> String {
        let name = camera.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKind = kind?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [
            trimmedKind?.isEmpty == false ? trimmedKind : nil,
            name.isEmpty ? "Kamera" : name,
            time(date, timeZone: timeZone),
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
