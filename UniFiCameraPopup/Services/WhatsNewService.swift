import Foundation

/// The new features of one app version, shown after an update.
struct ChangelogEntry: Identifiable, Equatable {
    var id: String { version }
    let version: String
    let items: [String]
}

/// What changed between the previously launched version and this one.
struct WhatsNewInfo: Equatable {
    let fromVersion: String
    let toVersion: String
    /// Newest version first.
    let entries: [ChangelogEntry]
}

/// Detects an app update across launches and collects the matching changelog.
///
/// Add an entry for every release whose `MARKETING_VERSION` is raised –
/// `scripts/build-release.sh` warns when the current version has none.
enum WhatsNewService {
    /// Newest version first.
    static let changelog: [ChangelogEntry] = [
        ChangelogEntry(version: "1.2.0", items: [
            "Einrichtung in wenigen Schritten: Die Konsole wird im Netzwerk gefunden, ein API-Schlüssel genügt.",
            "Popups bei Klingel, Person, Tier, Fahrzeug, Sprache und mehr – direkt aus Protect.",
            "Stream-Adressen holt die App selbst. Webhooks gibt es weiterhin unter „Erweitert“.",
            "Neue Einstellungen mit den Reitern Allgemein, Kameras, Ton und Unterwegs – hell, dunkel oder wie das System.",
            "Stummschalten pro Kamera direkt im Popup und für alle Kameras im Menü; die Dauern legst du selbst fest, und eine Stummschaltung bleibt auch nach einem Neustart bestehen.",
            "Das Popup zeigt Ereignis, Kamera und Uhrzeit, deine Buttons (z. B. „Tür öffnen“) haben jetzt Symbole.",
            "Sprechen und Ansagen: Bei Kameras mit Lautsprecher hältst du im Popup die Leertaste (oder den Button) und sprichst über die Kamera – im Modus „Umschalten“ tippst du einmal zum Starten und einmal zum Beenden. Fertige Ansagen spielst du als MP3 oder mit einer macOS-Stimme aus eigenem Text ab – einzurichten im Reiter Ton.",
            "Unterwegs: Mit der WireGuard-Datei deines Gateways erreicht die App deine Kameras auch außer Haus – "
                + "über einen eigenen Tunnel nur für die App, ganz ohne VPN in den Systemeinstellungen.",
        ]),
        ChangelogEntry(version: "1.1.1", items: [
            "Mehr Sicherheit: Die Bearer-Tokens der Aktions-Buttons werden jetzt im macOS-Schlüsselbund "
                + "gespeichert statt im Klartext in den Einstellungen. Bereits eingetragene Tokens werden automatisch übernommen.",
        ]),
        ChangelogEntry(version: "1.1.0", items: [
            "Aktions-Buttons: Pro Kamera kannst du bis zu 3 eigene Buttons (z. B. „Tür öffnen“) anlegen. "
                + "Sie erscheinen im Popup rechts neben den Stummschalt-Buttons und rufen eine Webhook-URL auf "
                + "(GET oder POST, optional mit Bearer-Token). Das Popup bleibt dabei geöffnet.",
            "Nach einem Update zeigt die App nun an, was sich seit deiner letzten Version geändert hat.",
        ]),
    ]

    private static let lastLaunchedVersionKey = "unifi.camera.popup.lastLaunchedVersion"
    /// Present on every installation that ran a build before this feature existed.
    private static let settingsKey = "unifi.camera.popup.settings"
    /// All builds before the introduction of semantic versions reported this.
    private static let legacyVersion = "1.0.0"

    private static var defaults: UserDefaults { .standard }

    /// Returns the changes since the last launched version, or `nil` on a fresh
    /// install, when nothing changed, or when the jump has no changelog entries.
    static func pendingUpdateInfo(currentVersion: String = AppConfig.shortVersion) -> WhatsNewInfo? {
        let previous: String
        if let stored = defaults.string(forKey: lastLaunchedVersionKey) {
            previous = stored
        } else if defaults.data(forKey: settingsKey) != nil {
            previous = legacyVersion
        } else {
            return nil
        }

        guard compare(previous, currentVersion) == .orderedAscending else { return nil }

        let entries = changelog.filter {
            compare(previous, $0.version) == .orderedAscending
                && compare($0.version, currentVersion) != .orderedDescending
        }
        guard !entries.isEmpty else { return nil }

        return WhatsNewInfo(fromVersion: previous, toVersion: currentVersion, entries: entries)
    }

    /// Records the running version so the same update is announced only once.
    static func markCurrentVersionSeen(_ version: String = AppConfig.shortVersion) {
        defaults.set(version, forKey: lastLaunchedVersionKey)
    }

    /// Compares dotted version strings numerically ("1.10.0" > "1.9.2").
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = components(of: lhs)
        let right = components(of: rhs)
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func components(of version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }
}
