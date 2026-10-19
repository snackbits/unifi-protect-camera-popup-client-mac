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
        ChangelogEntry(version: "2.6.1", items: [
            "Ansagen in Einstellungen › Ton haben links einen Griff zum Verschieben.",
            "Das Ansagen-Menü im Popup ist so breit wie der längste Name – nichts bricht mehr um.",
        ]),
        ChangelogEntry(version: "2.6.0", items: [
            "Ansagen lassen sich unter Einstellungen › Ton per Ziehen sortieren – das Ansagen-Menü im Popup folgt dieser Reihenfolge.",
            "Neue Text-Ansagen starten mit deiner meistgenutzten Stimme, sofern sie geladen ist – sonst mit einer bereits geladenen statt immer mit Thorsten.",
        ]),
        ChangelogEntry(version: "2.5.1", items: [
            "Den Kameraton-Schalter im Popup gibt es jetzt bei jeder Kamera mit Mikrofon – nicht nur bei Kameras mit Lautsprecher.",
        ]),
        ChangelogEntry(version: "2.5.0", items: [
            "Kameraton direkt im Popup: Der Lautsprecher rechts neben „Sprechen“ schaltet den Ton des Livebilds ein oder aus – und merkt sich das für die Kamera.",
            "Ansagen (MP3 und KI-Stimme) haben jetzt ein Megafon als Symbol.",
        ]),
        ChangelogEntry(version: "2.4.2", items: [
            "Standbilder (kein Livebild) passen jetzt ins Popup, statt es über den Bildschirmrand hinaus zu vergrößern.",
        ]),
        ChangelogEntry(version: "2.4.1", items: [
            "Kamera liefert kein Livebild (z. B. AV1 über Protects „Super Encoding“)? Das Popup zeigt dann jede Sekunde ein frisches Standbild und sagt, woran es liegt.",
            "Neue Versionen werden alle 30 Minuten und nach dem Aufwachen gesucht – die Update-Frage kommt also auch ohne Klick aufs Menüleisten-Symbol.",
        ]),
        ChangelogEntry(version: "2.4.0", items: [
            "Zahnrad im Popup (links neben der Glocke): öffnet direkt die Einstellungen dieser Kamera.",
        ]),
        ChangelogEntry(version: "2.3.0", items: [
            "Bei den Auslösern einer Kamera steht nur noch, was in Protect für sie eingeschaltet ist – Empfindlichkeit und Zonen stellst du weiter in Protect ein.",
            "Linienüberquerungen getrennt wählbar: „Person“, „Fahrzeug“ oder „Tier“ überquert Linie. Bisherige Auswahl bleibt erhalten.",
            "Ereignis-Regeln für Person, Fahrzeug oder Tier gelten jetzt nur für Erkennungen in Zonen – für Linien eine eigene Regel anlegen.",
        ]),
        ChangelogEntry(version: "2.2.0", items: [
            "Updates installieren sich nicht mehr unbemerkt: Bei einer neuen Version fragt die App nach und zeigt, was neu ist.",
            "Die Einstellung heißt jetzt „Bei neuer Version nachfragen“ (Allgemein).",
        ]),
        ChangelogEntry(version: "2.1.1", items: [
            "Behoben: Das Livebild blieb bei „Stream wird geladen …“ stehen, obwohl der Ton schon lief.",
        ]),
        ChangelogEntry(version: "2.1.0", items: [
            "Bildqualität pro Kamera (Hoch, Mittel, Niedrig – Standard Mittel): Niedriger startet das Livebild schneller.",
            "Kein schwarzes Popup mehr: Bis das erste Bild da ist, steht „Stream wird geladen …“.",
            "Ereignis, Kameraname und eine live mitlaufende Uhr stehen jetzt mittig oben im Popup – standardmäßig eingeschaltet.",
            "Alle Geheimnisse liegen in einem einzigen Schlüsselbund-Eintrag: weniger Passwortabfragen nach Updates.",
        ]),
        ChangelogEntry(version: "2.0.0", items: [
            "Einrichtung in wenigen Schritten: Die Konsole wird im Netzwerk gefunden, ein API-Schlüssel genügt.",
            "Popups bei Klingel, Person, Tier, Fahrzeug, Sprache und mehr – direkt aus Protect.",
            "Stream-Adressen holt die App selbst. Webhooks gibt es weiterhin unter „Erweitert“.",
            "Neue Einstellungen mit den Reitern Allgemein, Kameras, Ton und Unterwegs – hell, dunkel oder wie das System.",
            "Stummschalten pro Kamera direkt im Popup und für alle Kameras im Menü; die Dauern legst du selbst fest, und eine Stummschaltung bleibt auch nach einem Neustart bestehen.",
            "Deine Buttons im Popup (z. B. „Tür öffnen“) haben Symbole und können auch eine Ansage an der Kamera abspielen. Name und Uhrzeit blendet das Popup nur noch auf Wunsch ein (Kameras › Erweitert) – die Kamera zeigt beides ohnehin.",
            "Sprechen und Ansagen: Bei Kameras mit Lautsprecher hältst du im Popup den Button „Sprechen“ gedrückt und sprichst über die Kamera; Loslassen beendet. Fertige Ansagen spielst du als MP3 oder aus eigenem Text ab – gesprochen von Piper-Stimmen direkt auf dem Mac: acht deutsche Stimmen (Standard „Thorsten“) lädt die App beim ersten Gebrauch einmalig herunter. Sprechen und Ansagen kommen etwa gleich laut an, die Lautstärke regelst du für beides getrennt im Reiter Ton.",
            "Popups passen sich dem Bildschirm an: Zwei Kameras passen untereinander. Öffnen sich mehr, werden alle gleichmäßig kleiner und wachsen danach wieder auf ihre Größe.",
            "Ereignisse: Pro Kamera lösen Klingeln, Bewegung, Person, Fahrzeug, Tier oder Paket auf Wunsch einen Webhook und/oder eine Ansage aus – auch ohne Popup, während einer Stummschaltung und mit Verzögerung.",
            "Im Menü siehst du jetzt die Version und installierst ein Update direkt von dort.",
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
