import AppCore
import SwiftUI

/// Einstellungen › Unterwegs – layout of the template with its sample content, not interactive
/// until the tunnel exists (docs/design/einstellungen-unterwegs.md).
struct RemoteTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Tokens.accent.color).frame(width: 40, height: 40)
                    TemplateIcon.shieldCheck.image(size: 20).foregroundStyle(Color.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bereit · gerade zu Hause").font(.system(size: 14, weight: .bold))
                    Text("Der Tunnel springt an, sobald die Konsole nicht direkt erreichbar ist.")
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.muted.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Jetzt testen") {}.buttonStyle(FieldButtonStyle(vertical: 4, horizontal: 12))
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Tokens.accSoft.color))

            Card {
                FixedLabelRow(title: "Konfiguration", width: 140, vertical: 10, horizontal: 14) {
                    Text("macbook-camera-popup.conf").foregroundStyle(Tokens.muted.color).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Ersetzen …") {}.buttonStyle(FieldButtonStyle())
                }
                CardDivider()
                FixedLabelRow(title: "Gegenstelle", width: 140, vertical: 10, horizontal: 14) {
                    Text("[DEINE-HEIM-ADRESSE]:51820").foregroundStyle(Tokens.muted.color).frame(maxWidth: .infinity, alignment: .leading)
                }
                CardDivider()
                FixedLabelRow(title: "Letzte Verbindung", width: 140, vertical: 10, horizontal: 14) {
                    Text("gestern, 18:22 · über Mobilfunk").foregroundStyle(Tokens.muted.color).frame(maxWidth: .infinity, alignment: .leading)
                }
                CardDivider()
                CardRow(title: "Tunnel verwenden") {
                    PopUpField(selection: .constant(0), options: [(value: 0, title: "Automatisch")])
                }
            }

            HStack {
                Button("Anleitung: WireGuard auf dem UniFi-Gateway einrichten") {}.buttonStyle(LinkButtonStyle())
                Spacer()
                Button("Tunnel entfernen") {}.buttonStyle(LinkButtonStyle(color: Tokens.muted))
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 40)
        .allowsHitTesting(false)
    }
}
