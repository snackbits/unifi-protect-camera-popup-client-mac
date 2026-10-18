import AppCore
import AppKit
import ProtectKit
import SwiftUI

/// Kameras › Erweitert (docs/design/einstellungen-kameras.md, S3) plus the camera's popup options.
struct CameraAdvancedSection: View {
    @Binding var mapping: WebhookMapping
    let lastTriggered: Date?

    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var protect = ProtectSession.shared
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            webhookCard
            streamCard
            popupSection
            HStack {
                Button("Webhook jetzt testen") { PopupController.shared.showTestPopup(for: mapping) }
                    .buttonStyle(LinkButtonStyle())
                    .disabled(!mapping.hasStreamSource)
                Spacer()
                Text("Zuletzt ausgelöst: \(lastTriggered.map { DisplayText.dayAndTime($0, now: Date()) } ?? "noch nie")")
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.muted.color)
            }
        }
    }

    private var webhookCard: some View {
        Card(radius: 9) {
            CardToggleRow(
                title: "Zusätzlich per Webhook auslösen",
                subtitle: "Für Alarm Manager, Home Assistant oder andere Systeme.",
                isOn: $mapping.webhookTriggerEnabled,
                vertical: 10,
                horizontal: 12
            )
            if mapping.webhookTriggerEnabled {
                CardDivider()
                FixedLabelRow(title: "Webhook-ID") {
                    TokenTextField(placeholder: "z. B. haustuer-klingel", text: $mapping.webhookId)
                }
                CardDivider()
                FixedLabelRow(title: "Aufruf-Adresse") {
                    Text(callAddress)
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.muted.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(copied ? "Kopiert" : "Kopieren", action: copyAddress)
                        .buttonStyle(FieldButtonStyle())
                }
            }
        }
    }

    private var callAddress: String {
        AppConfig.webhookURL(
            installationId: settings.installationId,
            slug: mapping.webhookId.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private var streamCard: some View {
        Card(radius: 9) {
            FixedLabelRow(title: "Stream-Adresse") {
                TokenTextField(placeholder: "automatisch aus Protect", text: $mapping.rtspsURL)
                    .onChange(of: mapping.rtspsURL) { newValue in
                        let normalized = StreamURL.normalizedRTSP(newValue)
                        if normalized != newValue { mapping.rtspsURL = normalized }
                    }
            }
            CardDivider()
            Text("Nur ausfüllen, wenn der Stream nicht über die Protect-API kommen soll (rtsp://…:7447/…).")
                .font(.system(size: 11))
                .lineSpacing(3)
                .foregroundStyle(Tokens.muted.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            if let warning = streamURLWarning {
                CardDivider()
                Text(warning)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
            }
        }
    }

    private var popupSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Popup")
            Card(radius: 9) {
                FixedLabelRow(title: "Name") {
                    TokenTextField(placeholder: "z. B. Haustür", text: $mapping.label)
                }
                CardDivider()
                FixedLabelRow(title: "Protect-Kamera") {
                    PopUpField(selection: $mapping.protectCameraId, options: cameraOptions)
                    Spacer(minLength: 0)
                }
                .onChange(of: mapping.protectCameraId) { newId in applyDefaultTriggers(for: newId) }
                CardDivider()
                FixedLabelRow(title: "Position") {
                    PopUpField(selection: $mapping.positionOverride, options: positionOptions)
                    Spacer(minLength: 0)
                }
                CardDivider()
                FixedLabelRow(title: "Größe") {
                    TokenTextField(placeholder: "480", text: dimensionBinding($mapping.width)).frame(width: 64)
                    Text("×").foregroundStyle(Tokens.muted.color)
                    TokenTextField(placeholder: "270", text: dimensionBinding($mapping.height)).frame(width: 64)
                    Text("px").font(.system(size: 12)).foregroundStyle(Tokens.muted.color)
                    Spacer(minLength: 0)
                }
                CardDivider()
                CardToggleRow(title: "Name und Zeit einblenden", isOn: $mapping.showNameAndTime, vertical: 9, horizontal: 12)
                CardDivider()
                HStack(spacing: 8) {
                    if mapping.crop != nil {
                        Button("Ausschnitt löschen") { settings.removeCrop(for: mapping.entryId) }
                    } else {
                        Button("Ausschnitt setzen …") { PopupController.shared.showCropSelection(for: mapping) }
                            .disabled(!mapping.hasStreamSource)
                    }
                    Button("Test-Popup") { PopupController.shared.showTestPopup(for: mapping) }
                        .disabled(!mapping.hasStreamSource)
                    Spacer(minLength: 0)
                }
                .buttonStyle(FieldButtonStyle())
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
            }
        }
    }

    private var cameraOptions: [(value: String?, title: String)] {
        var options: [(value: String?, title: String)] = [(value: nil, title: "Keine (nur Webhook)")]
        options += protect.cameras.map { (value: Optional($0.id), title: $0.name) }
        if let id = mapping.protectCameraId, !protect.cameras.contains(where: { $0.id == id }) {
            options.append((value: id, title: "Unbekannte Kamera"))
        }
        return options
    }

    private var positionOptions: [(value: PopupPosition?, title: String)] {
        [(value: nil, title: "Standard")] + PopupPosition.allCases.map { (value: Optional($0), title: $0.label) }
    }

    /// A newly linked camera without triggers starts with Klingel + Person where supported.
    private func applyDefaultTriggers(for cameraId: String?) {
        guard mapping.triggers.isEmpty,
              let cameraId,
              let camera = protect.cameras.first(where: { $0.id == cameraId }) else { return }
        mapping.triggers = Set<TriggerKind>([.ring, .person]).intersection(camera.supportedTriggers)
    }

    private var streamURLWarning: String? {
        let trimmed = mapping.rtspsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().contains("rtsps://") { return "RTSPS wird nicht unterstützt. Bitte rtsp:// verwenden." }
        if trimmed.contains(":7441") { return "Port 7441 wird nicht unterstützt. Bitte Port 7447 verwenden." }
        if trimmed.lowercased().contains("enablesrtp") { return "?enableSrtp wird nicht unterstützt. Bitte entfernen." }
        return nil
    }

    private func dimensionBinding(_ value: Binding<Double>) -> Binding<String> {
        Binding(
            get: { String(Int(value.wrappedValue)) },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                guard !digits.isEmpty, let parsed = Double(digits) else { return }
                value.wrappedValue = parsed
            }
        )
    }

    private func copyAddress() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(callAddress, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }
}
