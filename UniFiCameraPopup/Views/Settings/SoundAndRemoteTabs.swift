import AppCore
import SwiftUI

/// Einstellungen › Ton – layout of the template with its sample content, not interactive
/// until talkback and announcements exist (docs/design/einstellungen-ton.md).
struct SoundTab: View {
    private struct SampleSound: Identifiable {
        let id: String
        let length: String
        let tag: String
        let selected: Bool
        var isMP3: Bool { tag == "MP3" }
    }

    private let samples = [
        SampleSound(id: "Gong", length: "0:02", tag: "MP3", selected: false),
        SampleSound(id: "Bin gleich da", length: "0:03", tag: "KI-STIMME", selected: true),
        SampleSound(id: "Paket bitte abstellen", length: "0:05", tag: "KI-STIMME", selected: false),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                SectionLabel(text: "Ansagen für „Ton abspielen“")
                Card {
                    ForEach(samples) { sound in
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(Tokens.accSoft.color).frame(width: 22, height: 22)
                                TemplateIcon.play.image(size: 9).foregroundStyle(Tokens.accText.color)
                            }
                            Text(sound.id).fontWeight(.medium).frame(maxWidth: .infinity, alignment: .leading)
                            Text(sound.length)
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(Tokens.muted.color)
                            Text(sound.tag)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.vertical, 2)
                                .padding(.horizontal, 6)
                                .foregroundStyle(sound.isMP3 ? Tokens.muted.color : Tokens.accText.color)
                                .background(RoundedRectangle(cornerRadius: 4)
                                    .fill(sound.isMP3 ? Tokens.btn2.color : Tokens.accSoft.color))
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(sound.selected ? Tokens.accSoft.color : Color.clear)
                        CardDivider()
                    }
                    HStack(spacing: 14) {
                        Button("MP3 hinzufügen …") {}.buttonStyle(LinkButtonStyle())
                        Button("Ansage aus Text …") {}.buttonStyle(LinkButtonStyle())
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("„Bin gleich da“").fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading)
                    TokenSegmented(selection: .constant(1), options: [(value: 0, title: "MP3-Datei"), (value: 1, title: "KI-Stimme")])
                }
                TokenTextField(placeholder: "", text: .constant("Bin gleich da! Einen kleinen Moment, bitte."),
                               fontSize: 13, vertical: 5, horizontal: 8, radius: 6)
                HStack(spacing: 8) {
                    Text("Stimme").font(.system(size: 12)).foregroundStyle(Tokens.muted.color)
                    PopUpField(selection: .constant(0), options: [(value: 0, title: "Anna (Premium) · macOS")])
                    Spacer()
                    Button("Anhören") {}.buttonStyle(FieldButtonStyle())
                    Button("Übernehmen") {}.buttonStyle(AccentButtonStyle(fontSize: 12, vertical: 3, horizontal: 10))
                }
                Text("Wird auf diesem Mac erzeugt – ohne Internet, ohne Konto.")
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.muted.color)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Tokens.group.color))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tokens.accent.color, lineWidth: 1))

            Card {
                CardRow(title: "Mikrofon") {
                    PopUpField(selection: .constant(0), options: [(value: 0, title: "MacBook Pro-Mikrofon")])
                }
                CardDivider()
                CardRow(title: "Sprechen") {
                    TokenSegmented(selection: .constant(0), options: [(value: 0, title: "Leertaste halten"), (value: 1, title: "Umschalten")])
                }
                CardDivider()
                CardRow(title: "Lautstärke an der Kamera") { VolumeTrack() }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 40)
        .allowsHitTesting(false)
    }
}

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
