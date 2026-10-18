import AppCore
import SwiftUI

/// General WireGuard guide, opened from „Ausführliche Anleitung öffnen“ (Einrichtung)
/// and „Anleitung: WireGuard auf dem UniFi-Gateway einrichten“ (Reiter „Unterwegs“).
struct WireGuardGuideView: View {
    @Environment(\.dismiss) private var dismiss

    static let steps: [(title: String, text: String)] = [
        ("WireGuard-Server anlegen",
         "Öffne in der UniFi-Network-Oberfläche Einstellungen → VPN → VPN-Server und lege einen Server vom Typ „WireGuard“ an. "
            + "Andere Router (z. B. FRITZ!Box) bieten das meist unter „VPN“ oder „Fernzugang“."),
        ("Client für diesen Mac hinzufügen",
         "Füge dem Server einen Client (Peer) hinzu, etwa „MacBook Camera Popup“. Lege für jedes Gerät einen eigenen Client an."),
        ("Von außen erreichbar machen",
         "Der Server braucht eine feste öffentliche Adresse oder einen DynDNS-Namen. Ein UniFi-Gateway öffnet seinen Port "
            + "(Standard: UDP 51820) selbst. Sitzt davor ein weiterer Router, leite dort UDP 51820 an das Gateway weiter."),
        ("Datei herunterladen",
         "Lade die Konfiguration des Clients als .conf-Datei herunter – bei UniFi über „Herunterladen“ beim Client."),
        ("In der App ablegen",
         "Zieh die Datei auf „WireGuard-Datei hier ablegen“ oder wähle sie über „Ersetzen …“ aus. Der Schlüssel liegt danach "
            + "im Schlüsselbund dieses Macs und nie im Konfigurations-Export."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("WireGuard einrichten")
                .font(.system(size: 20, weight: .bold))
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Tokens.accent.color))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.title).font(.system(size: 13, weight: .semibold))
                                Text(step.text)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Tokens.muted.color)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Text("Die App nutzt den Tunnel nur für ihre eigenen Verbindungen zur Konsole. Dein übriger Datenverkehr bleibt, "
                         + "wie er ist – ein VPN in den Systemeinstellungen ist nicht nötig. Zu Hause verbindet sich die App direkt.")
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.muted.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(24)
            }
            Divider()
            HStack {
                Spacer()
                Button("Schließen") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 500)
    }
}
