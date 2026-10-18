import SwiftUI

struct HelpView: View {
    private enum Topic: String, CaseIterable, Identifiable {
        case setup = "Setup"
        case tips = "Tipps"
        case troubleshooting = "Problemlösung"
        case about = "Über"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .setup: return "wrench.and.screwdriver"
            case .tips: return "lightbulb"
            case .troubleshooting: return "stethoscope"
            case .about: return "info.circle"
            }
        }
    }

    @State private var selection: Topic = .setup

    var body: some View {
        NavigationSplitView {
            List(Topic.allCases, selection: $selection) { topic in
                Label(topic.rawValue, systemImage: topic.icon)
                    .tag(topic)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            VStack(spacing: 0) {
                detailHeader
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                    .background(.background)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selection {
                        case .setup: setupBody
                        case .tips: tipsBody
                        case .troubleshooting: troubleshootingBody
                        case .about: aboutBody
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    @ViewBuilder
    private var detailHeader: some View {
        switch selection {
        case .setup:
            header("Setup", subtitle: "So richtest du die App Schritt für Schritt ein.")
        case .tips:
            header("Tipps", subtitle: "Kleine Kniffe für den Alltag.")
        case .troubleshooting:
            header("Problemlösung", subtitle: "Wenn das App-Symbol rot ist.")
        case .about:
            header("Über", subtitle: "Version und Lizenzen.")
        }
    }

    // MARK: - Setup

    private var setupBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            step(1, "Menüleisten-Symbol",
                 "Nach dem Start erscheint oben in der Menüleiste das Kamera-Symbol. "
                 + "Ist es grün, besteht eine Verbindung zum Server. Über das Symbol öffnest du die Einstellungen.")

            step(2, "Webhook-URL kopieren",
                 "In den Einstellungen findest du oben deine persönliche Webhook-URL. "
                 + "Du brauchst sie später in UniFi Protect.")

            step(3, "Kamera anlegen",
                 "Lege in den Einstellungen für jede Kamera einen Eintrag an und vergib einen Slug "
                 + "(z. B. „haustuer“). Dieser Slug ersetzt den Platzhalter in der Webhook-URL.")

            step(4, "RTSP-Stream eintragen",
                 "In den UniFi-Protect-Kamera-Einstellungen findest du die RTSP-Links. "
                 + "Nimm am besten den Medium-Stream – High Quality ist unnötig groß und verlängert "
                 + "den Verbindungsaufbau. Trag den Link beim Kamera-Eintrag ein.")

            step(5, "Alarm in UniFi Protect erstellen",
                 "Öffne den UniFi Alarm Manager und erstelle einen Alarm, der einen Webhook auslöst. "
                 + "Trag dort deine Webhook-URL mit dem passenden Slug der Kamera ein. "
                 + "Aktiviere anschließend „Erweiterte Einstellungen“ und setze: "
                 + "Methode auf „POST“, Authentifizierung auf „Bearer“, "
                 + "trage den Webhook-Token unter „Token“ ein und aktiviere „Vorschaubilder verwenden“. "
                 + "Manche Unifi Versionen machen Probleme mit Vorschaubildern. "
                 + "In diesem Fall solltest du das Vorschaubild deaktivieren, wenn sich bei dir kein Popup öffnet.")

            step(6, "Zugriff von unterwegs (optional)",
                 "Standardmäßig funktioniert alles nur im lokalen Netzwerk. Für den Zugriff von unterwegs "
                 + "ersetzt du die lokale IP durch einen von außen erreichbaren Hostnamen und gibst Port 7447 "
                 + "(nicht 7441!) auf deiner Dream Machine frei. Alternativ – und generell empfehlenswert – "
                 + "nutzt du ein VPN ins Heimnetz.")

            step(7, "Encoding beachten",
                 "Hörst du nur Ton deiner Kamera, aber siehst kein Bild, ist die Kamera vermutlich auf „Advanced“-Encoding eingestellt. "
                 + "Dieses nutzt einen Codec, den das Popup nicht abspielen kann. Stelle die Kamera auf „Standard“ "
                 + "oder „Enhanced“ – damit funktioniert die Wiedergabe.")
        }
    }

    // MARK: - Tips

    private var tipsBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            tip("Popup schließen", "rectangle.slash",
                "Mit einem Links- oder Rechtsklick auf das Popup schließt du es sofort.")

            tip("Fenster offen halten", "cursorarrow.rays",
                "Solange sich der Mauszeiger über dem Popup befindet, bleibt es geöffnet "
                + "und schließt nicht automatisch.")

            tip("Zoomen", "plus.magnifyingglass",
                "Scrolle mit dem Mausrad über dem Video – oder zieh am Trackpad mit zwei Fingern auf – "
                + "um ins Bild hineinzuzoomen. Genauso kannst du wieder herauszoomen. Im hineingezoomten "
                + "Zustand verschiebst du den Bildausschnitt mit gedrückter Maustaste (Klicken und Ziehen). "
                + "Zum Schließen nutzt du im gezoomten Zustand den Rechtsklick. Ein Linksklick schließt das Popup im gezoomten Zustand nicht.")

            tip("Popups stummschalten", "bell.slash",
                "Über die beiden Buttons oben rechts im Popup unterdrückst du alle Popups – "
                + "links für 1 Stunde, rechts für 15 Minuten. Die Stummschaltung hebst du jederzeit "
                + "über das Menüleisten-Symbol wieder auf.")

            tip("Aktions-Buttons", "bolt",
                "Pro Kamera kannst du in den Einstellungen bis zu 3 eigene Buttons anlegen – z. B. „Tür öffnen“. "
                + "Gib dafür einen Titel und eine Webhook-URL an, wähle GET oder POST und trage bei Bedarf "
                + "einen Bearer-Token ein. Die Buttons erscheinen im Popup oben rechts neben den Stummschalt-Buttons. "
                + "Ein Klick ruft die URL auf (z. B. einen Home-Assistant-Webhook oder ein Shelly-Relais), "
                + "das Popup bleibt dabei geöffnet. Ein Häkchen bestätigt den Erfolg, ein Warndreieck zeigt einen Fehler – "
                + "die Details siehst du im Tooltip. Mit „Testen“ in den Einstellungen prüfst du die URL vorab. "
                + "Bei Kameras mit Lautsprecher kann ein Button zusätzlich (oder statt des Webhooks) eine Ansage aus dem Reiter Ton an der Kamera abspielen – "
                + "ist ein Ton gewählt, ist die Adresse optional.")

            tip("Ereignisse", "bell.badge",
                "Unter Einstellungen › Kameras › Ereignisse legst du pro Kamera Regeln an: Bei Klingeln, Bewegung, Person, Fahrzeug, Tier oder Paket "
                + "ruft die App einen Webhook auf und/oder spielt eine Ansage an der Kamera ab – auf Wunsch mit Verzögerung (bis 600 Sekunden). "
                + "Regeln laufen auch ohne Popup und während einer Stummschaltung; dieselbe Regel löst höchstens alle 30 Sekunden aus. "
                + "Ausgeführte Regeln erscheinen im Menü unter den letzten Ereignissen.")

            tip("Sprechen und Ansagen", "mic",
                "Bei Kameras mit Lautsprecher zeigt das Popup unten „Ton abspielen“ und „Sprechen“. "
                + "Halte „Sprechen“ mit der Maus gedrückt und sprich; Loslassen beendet – auch wenn der Zeiger dabei das Popup verlässt. "
                + "Die App gleicht dein Mikrofon automatisch an die Lautstärke der Ansagen an. Unter Einstellungen › Ton wählst du das Mikrofon, "
                + "regelst „Lautstärke Sprechen“ und „Lautstärke Ansagen“ getrennt und verwaltest "
                + "die Ansagen (MP3 oder Text, gesprochen von der macOS-Stimme Anna, erzeugt auf diesem Mac). Die mitgelieferten Ansagen "
                + "„Bin gleich da“ und „Paket bitte abstellen“ wurden mit Piper und der Stimme „Thorsten“ erzeugt "
                + "(Datensatz CC0, gemeinfrei). Klappt etwas nicht, steht der Ablauf in "
                + "~/Library/Logs/UniFi Camera Popup/talkback.log.")

            tip("Unterwegs", "shield",
                "Mit der WireGuard-Datei deines Gateways erreicht die App die Konsole auch außer Haus. "
                + "Webhook-Buttons mit „http“ funktionieren dann nur, wenn ihre Ziel-IP im Tunnel liegt; "
                + "Buttons mit „https“ gehen direkt. Namen auf „.local“ lassen sich unterwegs nicht auflösen. "
                + "Steht in der Datei ein DynDNS-Name als Endpoint und ändert sich die IP zu Hause, "
                + "löst die App den Namen nach etwa drei Minuten ohne Antwort neu auf und verbindet sich wieder. "
                + "Solange der Tunnel läuft, können andere Programme auf diesem Mac alles erreichen, was die App weiterleitet: "
                + "die Konsole (meist Port 443), die Kamera-Streams und die Webhook-Ziele im Heimnetz. "
                + "Die Protect-API bleibt durch Zertifikats-Pin und API-Schlüssel geschützt.")
        }
    }

    // MARK: - Troubleshooting

    private var troubleshootingBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ein rotes Symbol in der Menüleiste bedeutet, dass keine Verbindung zum Server besteht "
                 + "und keine Popups ausgelöst werden können. Mögliche Ursachen:")
                .fixedSize(horizontal: false, vertical: true)

            tip("Keine Internetverbindung", "wifi.exclamationmark",
                "Prüfe, ob dein Mac mit dem Internet verbunden ist. Sobald die Verbindung steht, "
                + "wird das Symbol automatisch wieder grün.")

            tip("Veraltete App-Version", "arrow.triangle.2.circlepath",
                "Ist die App veraltet, trennt der Server die Verbindung. Aktualisiere die App über "
                + "das Menüleisten-Symbol („Auf neue Version aktualisieren“), sobald ein Update verfügbar ist.")

            tip("Server-Wartung", "wrench.and.screwdriver",
                "Eventuell wird gerade eine Wartung durchgeführt. Warte ein paar Minuten – "
                + "die Verbindung stellt sich danach von selbst wieder her.")
        }
    }

    // MARK: - Über

    private var aboutBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Camera Popup \(AppConfig.shortVersion) (Build \(AppConfig.buildNumber))")
                .font(.headline)
            Text("Der Tunnel für unterwegs verwendet freie Software: wireguard-go (MIT-Lizenz, © WireGuard LLC), "
                 + "gVisor (Apache-Lizenz 2.0, © The gVisor Authors) und die Go-Laufzeit samt golang.org/x-Bibliotheken "
                 + "(BSD-3-Clause, © The Go Authors) sowie google/btree (Apache-Lizenz 2.0). "
                 + "„WireGuard“ ist eine eingetragene Marke von Jason A. Donenfeld.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Die mitgelieferten Ansagen „Bin gleich da“ und „Paket bitte abstellen“ wurden mit Piper und der "
                 + "Stimme „Thorsten“ erzeugt (Datensatz CC0, gemeinfrei).")
                .fixedSize(horizontal: false, vertical: true)
            Text(Self.thirdPartyNotices)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Full license texts, generated by `wgtunnel/scripts/collect-notices.sh`.
    private static let thirdPartyNotices: String = {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Lizenztexte fehlen im App-Paket."
        }
        return text
    }()

    // MARK: - Building blocks

    private func header(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.largeTitle.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func step(_ number: Int, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tip(_ title: String, _ icon: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
