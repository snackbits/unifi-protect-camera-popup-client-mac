import SwiftUI

struct HelpView: View {
    private enum Topic: String, CaseIterable, Identifiable {
        case setup = "Setup"
        case tips = "Tipps"
        case troubleshooting = "Problemlösung"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .setup: return "wrench.and.screwdriver"
            case .tips: return "lightbulb"
            case .troubleshooting: return "stethoscope"
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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selection {
                    case .setup: setupContent
                    case .tips: tipsContent
                    case .troubleshooting: troubleshootingContent
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    // MARK: - Setup

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Setup", subtitle: "So richtest du die App Schritt für Schritt ein.")

            step(1, "Menüleisten-Symbol",
                 "Nach dem Start erscheint oben in der Menüleiste das Kamera-Symbol. "
                 + "Ist es grün, besteht eine Verbindung zum Server. Über das Symbol öffnest du die Einstellungen.")

            step(2, "Webhook-URL kopieren",
                 "In den Einstellungen findest du oben deine persönliche Webhook-URL. "
                 + "Du brauchst sie später in UniFi Protect. Ein eigener Server ist nicht nötig.")

            step(3, "Kamera anlegen",
                 "Lege in den Einstellungen für jede Kamera einen Eintrag an und vergib einen Slug "
                 + "(z. B. „haustuer“). Dieser Slug ersetzt den Platzhalter in der Webhook-URL.")

            step(4, "RTSP-Stream eintragen",
                 "In den UniFi-Protect-Kamera-Einstellungen findest du die RTSP-Links. "
                 + "Nimm am besten den Medium-Stream – High Quality ist unnötig groß und verlängert "
                 + "den Verbindungsaufbau. Trag den Link beim Kamera-Eintrag ein.")

            step(5, "Alarm in UniFi Protect erstellen",
                 "Öffne den UniFi Alarm Manager und erstelle einen Alarm, der einen Webhook auslöst. "
                 + "Trag dort deine Webhook-URL mit dem passenden Slug der Kamera ein.")

            step(6, "Zugriff von unterwegs (optional)",
                 "Standardmäßig funktioniert alles nur im lokalen Netzwerk. Für den Zugriff von unterwegs "
                 + "ersetzt du die lokale IP durch einen von außen erreichbaren Hostnamen und gibst Port 7447 "
                 + "(nicht 7441!) auf deiner Dream Machine frei. Alternativ – und generell empfehlenswert – "
                 + "nutzt du ein VPN ins Heimnetz.")

            step(7, "Encoding beachten",
                 "Siehst du nur Ton, aber kein Bild, ist die Kamera vermutlich auf „Advanced“-Encoding eingestellt. "
                 + "Dieses nutzt einen Codec, den nur UniFi selbst abspielen kann. Stelle die Kamera auf „Standard“ "
                 + "oder „Enhanced“ – damit funktioniert die Wiedergabe.")
        }
    }

    // MARK: - Tips

    private var tipsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Tipps", subtitle: "Kleine Kniffe für den Alltag.")

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
        }
    }

    // MARK: - Troubleshooting

    private var troubleshootingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Problemlösung", subtitle: "Wenn das App-Symbol rot ist.")

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

    // MARK: - Building blocks

    private func header(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.largeTitle.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
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
