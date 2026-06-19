import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var webSocketClient: WebSocketClient

    @State private var showRegenerateConfirm = false
    @State private var copiedWebhookURL = false
    @State private var copiedBearerToken = false
    @State private var dndHasFullDiskAccess = true

    var body: some View {
        Form {
            Section("Verbindung") {
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                    Text(webSocketClient.status.menuLabel)
                    Spacer()
                }

                if webSocketClient.status == .outdated {
                    Label(
                        "Veraltete App-Version. Bitte aktualisiere die App.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Eindeutige ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(settings.installationId)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Neue ID") {
                            showRegenerateConfirm = true
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Webhook URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(webhookURL)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(copiedWebhookURL ? "Kopiert" : "Kopieren") {
                            copyWebhookURL()
                        }
                    }
                    Text("\(AppConfig.webhookSlugPlaceholder) durch den jeweiligen Webhook-Slug der Kamera ersetzen.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Bearer Token")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(AppConfig.webhookToken)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(copiedBearerToken ? "Kopiert" : "Kopieren") {
                            copyBearerToken()
                        }
                    }
                    Text("Für „Authentifizierung“ → „Bearer“ → „Token“ im UniFi Alarm Manager.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Popup") {
                Picker("Position", selection: $settings.defaultPosition) {
                    ForEach(PopupPosition.allCases) { position in
                        Text(position.label).tag(position)
                    }
                }

                Picker("Bildschirm", selection: $settings.screenTarget) {
                    ForEach(ScreenTarget.allCases) { target in
                        Text(target.label).tag(target)
                    }
                }

                HStack {
                    Text("Randabstand")
                    Slider(value: $settings.edgeMargin, in: 0...120, step: 1)
                    Text("\(Int(settings.edgeMargin)) px")
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                }

                HStack {
                    Text("Auto-Schließen")
                    Slider(value: $settings.autoCloseTimeout, in: 0...300, step: 5)
                    Text(settings.autoCloseTimeout > 0 ? "\(Int(settings.autoCloseTimeout)) s" : "Aus")
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Alle aktiven Kameras zeigen", isOn: $settings.showAllActiveCameras)
                    Text("Jede auslösende Kamera bekommt ein eigenes Popup, untereinander gestapelt. Ohne diese Option ersetzt eine neue Kamera das aktuelle Popup.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Kameras") {
                ForEach($settings.mappings) { $mapping in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Beschreibung (z. B. Eingang)", text: $mapping.label)
                            .textFieldStyle(.roundedBorder)
                        TextField("Webhook-Slug (z. B. front-door)", text: $mapping.webhookId)
                            .textFieldStyle(.roundedBorder)
                        TextField("RTSP URL", text: $mapping.rtspsURL, prompt: Text("rtsp://user:pass@host:7447/…"))
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: mapping.rtspsURL) { newValue in
                                let normalized = normalizeRTSP(newValue)
                                if normalized != newValue {
                                    mapping.rtspsURL = normalized
                                }
                            }

                        if let warning = streamURLWarning(for: mapping.rtspsURL) {
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        Toggle("Ton", isOn: $mapping.soundEnabled)
                        Toggle("Zoom merken", isOn: $mapping.rememberZoom)

                        Picker("Position (optional)", selection: Binding<PopupPosition?>(
                            get: { mapping.positionOverride },
                            set: { mapping.positionOverride = $0 }
                        )) {
                            Text("Standard").tag(nil as PopupPosition?)
                            ForEach(PopupPosition.allCases) { position in
                                Text(position.label).tag(Optional(position))
                            }
                        }

                        TextField("Breite (px)", text: dimensionBinding($mapping.width), prompt: Text("480"))
                            .textFieldStyle(.roundedBorder)
                        TextField("Höhe (px)", text: dimensionBinding($mapping.height), prompt: Text("270"))
                            .textFieldStyle(.roundedBorder)

                        HotkeyRecorderView(
                            hotkey: $mapping.hotkey,
                            conflictMessage: hotkeyConflictMessage(for: mapping)
                        )

                        HStack {
                            Spacer()
                            if mapping.crop != nil {
                                Button("Ausschnitt löschen") {
                                    settings.removeCrop(for: mapping.id)
                                }
                            } else {
                                Button("Ausschnitt setzen") {
                                    PopupController.shared.showCropSelection(for: mapping)
                                }
                                .disabled(!canTestPopup(mapping))
                            }
                            Button("Test-Popup") {
                                PopupController.shared.showTestPopup(for: mapping)
                            }
                            .disabled(!canTestPopup(mapping))
                            Button("Entfernen", role: .destructive) {
                                settings.removeMapping(id: mapping.id)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                HStack {
                    Button("Kamera hinzufügen") {
                        settings.addMapping()
                    }
                    Spacer()
                }
            }

            Section("System") {
                Toggle("Beim Login starten", isOn: $settings.launchAtLogin)
                Toggle("Automatisch aktualisieren", isOn: $settings.autoUpdate)
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Bei DND deaktivieren (🧪 LAB)", isOn: $settings.disableDuringDND)
                    Text("Keine Popups, während ein „Nicht stören“- oder Fokus-Modus aktiv ist.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if settings.disableDuringDND && !dndHasFullDiskAccess {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(
                                "Ohne „Festplattenvollzugriff“ kann der Fokus-/Nicht-stören-Status nicht erkannt werden.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            Button("Festplattenvollzugriff öffnen") {
                                openFullDiskAccessSettings()
                            }
                            .controlSize(.small)
                            Text("Aktiviere „UniFi Camera Popup“ in der Liste und starte die App danach neu.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { refreshDNDPermission() }
        .onChange(of: settings.disableDuringDND) { _ in refreshDNDPermission() }
        .alert("Neue ID generieren?", isPresented: $showRegenerateConfirm) {
            Button("Abbrechen", role: .cancel) {}
            Button("Neue ID", role: .destructive) {
                settings.regenerateInstallationId()
            }
        } message: {
            Text("Die Webhook URLs ändern sich. Du musst die Webhooks in UniFi Protect anschließend neu eintragen.")
        }
    }

    private var statusColor: Color {
        switch webSocketClient.status {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected, .outdated: return .red
        }
    }

    private var webhookURL: String {
        AppConfig.webhookURL(installationId: settings.installationId)
    }

    private func copyWebhookURL() {
        copyToPasteboard(webhookURL) {
            copiedWebhookURL = true
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                copiedWebhookURL = false
            }
        }
    }

    private func copyBearerToken() {
        copyToPasteboard(AppConfig.webhookToken) {
            copiedBearerToken = true
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                copiedBearerToken = false
            }
        }
    }

    private func copyToPasteboard(_ string: String, onCopied: () -> Void) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        onCopied()
    }

    private func refreshDNDPermission() {
        guard settings.disableDuringDND else {
            dndHasFullDiskAccess = true
            return
        }
        dndHasFullDiskAccess = DoNotDisturbChecker.hasFullDiskAccess
    }

    private func openFullDiskAccessSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func canTestPopup(_ mapping: WebhookMapping) -> Bool {
        !mapping.webhookId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !mapping.rtspsURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func hotkeyConflictMessage(for mapping: WebhookMapping) -> String? {
        guard let hotkey = mapping.hotkey else { return nil }

        let duplicates = settings.mappings.filter { $0.hotkey == hotkey }
        if duplicates.count > 1 {
            return conflictNamesMessage(
                prefix: "Dieses Tastenkürzel ist",
                mappings: duplicates
            )
        }

        if hotkey.isSequence, let prefix = hotkey.steps.first {
            let singleKeyConflicts = settings.mappings.filter {
                guard mapping.entryId != $0.entryId, let other = $0.hotkey else { return false }
                return !other.isSequence && other.steps.first == prefix
            }
            if !singleKeyConflicts.isEmpty {
                return conflictNamesMessage(
                    prefix: "Die erste Taste kollidiert mit dem Einzel-Shortcut von",
                    mappings: singleKeyConflicts
                )
            }
        }

        if !hotkey.isSequence, let prefix = hotkey.steps.first {
            let sequenceConflicts = settings.mappings.filter {
                guard mapping.entryId != $0.entryId, let other = $0.hotkey else { return false }
                return other.isSequence && other.steps.first == prefix
            }
            if !sequenceConflicts.isEmpty {
                return conflictNamesMessage(
                    prefix: "Dieser Shortcut blockiert die Sequenz von",
                    mappings: sequenceConflicts
                )
            }
        }

        return nil
    }

    private func conflictNamesMessage(prefix: String, mappings: [WebhookMapping]) -> String {
        let names = mappings
            .map { $0.label.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if names.isEmpty {
            return "\(prefix) mehreren Kameras."
        }
        return "\(prefix) \(names.joined(separator: ", "))."
    }

    private func streamURLWarning(for url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().contains("rtsps://") {
            return "RTSPS wird nicht unterstützt. Bitte rtsp:// verwenden."
        }
        if trimmed.contains(":7441") {
            return "Port 7441 wird nicht unterstützt. Bitte Port 7447 verwenden."
        }
        if trimmed.lowercased().contains("enablesrtp") {
            return "?enableSrtp wird nicht unterstützt. Bitte entfernen."
        }
        return nil
    }

    /// Normalizes a UniFi RTSP URL: rtsps:// → rtsp://, :7441 → :7447,
    /// and removes the enableSrtp query parameter. Idempotent.
    private func normalizeRTSP(_ url: String) -> String {
        var result = url

        if let range = result.range(of: "rtsps://", options: .caseInsensitive) {
            result.replaceSubrange(range, with: "rtsp://")
        }

        result = result.replacingOccurrences(of: ":7441", with: ":7447")

        result = result.replacingOccurrences(
            of: "[?&]enableSrtp(=[^&]*)?",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // If removing the first query parameter left a dangling "&", promote it to "?".
        if !result.contains("?"), let amp = result.firstIndex(of: "&") {
            result.replaceSubrange(amp...amp, with: "?")
        }

        return result
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
}
