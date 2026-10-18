import AppKit
import ProtectKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var webSocketClient: WebSocketClient
    @ObservedObject private var protect = ProtectSession.shared

    @State private var showRegenerateConfirm = false
    @State private var mappingPendingRemoval: WebhookMapping?
    @State private var copiedWebhookURL = false
    @State private var copiedBearerToken = false
    @State private var dndHasFullDiskAccess = true
    @State private var launchRequiresApproval = false
    @State private var pendingImportData: Data?
    @State private var transferError: String?

    var body: some View {
        Form {
            Section("UniFi Protect") {
                LabeledContent("Konsole") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(protect.lastError == nil && settings.isProtectConfigured ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(settings.protectHost.isEmpty ? "nicht eingerichtet" : settings.protectHost)
                            .foregroundStyle(.secondary)
                        Button("Einrichtung …") { OnboardingWindow.show() }
                    }
                }
                if let error = protect.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    if error == ProtectError.certificateChanged.errorDescription {
                        Button("Neuem Zertifikat vertrauen") {
                            settings.protectCertificateFingerprint = nil
                            ProtectSession.shared.reconnect()
                        }
                    }
                }
            }

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
                        protectControls($mapping)

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

                        CameraActionsEditor(actions: $mapping.actions)

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
                            Button("Kamera entfernen", role: .destructive) {
                                mappingPendingRemoval = mapping
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
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Beim Login starten", isOn: $settings.launchAtLogin)

                    if launchRequiresApproval {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(
                                "„UniFi Camera Popup“ muss in den Anmeldeobjekten freigegeben werden, sonst startet die App nicht automatisch.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            Button("Anmeldeobjekte öffnen") {
                                LaunchAtLoginHelper.openLoginItemsSettings()
                            }
                            .controlSize(.small)
                        }
                        .padding(.top, 4)
                    }
                }
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

            Section("Konfiguration") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Exportiere die komplette Einrichtung (eindeutige ID, Kameras und Einstellungen) und importiere sie auf einem anderen Mac, um beide identisch zu konfigurieren.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Konfiguration exportieren…") {
                            exportConfiguration()
                        }
                        Button("Konfiguration importieren…") {
                            chooseConfigurationToImport()
                        }
                        Spacer()
                    }
                    Text("Die Exportdatei enthält deine eindeutige ID und die Bearer-Tokens der Aktions-Buttons – teile sie nur mit deinen eigenen Geräten.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task { await ProtectSession.shared.refreshCameras() }
        .padding()
        .onAppear {
            refreshDNDPermission()
            refreshLaunchApprovalState()
        }
        .onChange(of: settings.disableDuringDND) { _ in refreshDNDPermission() }
        .onChange(of: settings.launchAtLogin) { _ in refreshLaunchApprovalState() }
        .alert("Neue ID generieren?", isPresented: $showRegenerateConfirm) {
            Button("Abbrechen", role: .cancel) {}
            Button("Neue ID", role: .destructive) {
                settings.regenerateInstallationId()
            }
        } message: {
            Text("Die Webhook URLs ändern sich. Du musst die Webhooks in UniFi Protect anschließend neu eintragen.")
        }
        .alert(
            "Kamera entfernen?",
            isPresented: Binding(
                get: { mappingPendingRemoval != nil },
                set: { if !$0 { mappingPendingRemoval = nil } }
            ),
            presenting: mappingPendingRemoval
        ) { mapping in
            Button("Abbrechen", role: .cancel) {}
            Button("Entfernen", role: .destructive) {
                settings.removeMapping(id: mapping.id)
            }
        } message: { mapping in
            let name = mapping.label.trimmingCharacters(in: .whitespacesAndNewlines)
            Text(name.isEmpty
                ? "Möchtest du diese Kamera wirklich entfernen?"
                : "Möchtest du die Kamera „\(name)“ wirklich entfernen?")
        }
        .alert(
            "Konfiguration importieren?",
            isPresented: Binding(
                get: { pendingImportData != nil },
                set: { if !$0 { pendingImportData = nil } }
            )
        ) {
            Button("Abbrechen", role: .cancel) { pendingImportData = nil }
            Button("Importieren", role: .destructive) { confirmImport() }
        } message: {
            Text("Die aktuelle Konfiguration wird vollständig ersetzt – einschließlich der eindeutigen ID und aller Kameras.")
        }
        .alert(
            "Import fehlgeschlagen",
            isPresented: Binding(
                get: { transferError != nil },
                set: { if !$0 { transferError = nil } }
            ),
            presenting: transferError
        ) { _ in
            Button("OK", role: .cancel) { transferError = nil }
        } message: { message in
            Text(message)
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

    private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "unifi-camera-popup-config.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try settings.exportedConfigurationData()
            try data.write(to: url)
        } catch {
            transferError = error.localizedDescription
        }
    }

    private func chooseConfigurationToImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // Hold the file contents until the user confirms the overwrite.
            pendingImportData = try Data(contentsOf: url)
        } catch {
            transferError = error.localizedDescription
        }
    }

    private func confirmImport() {
        guard let data = pendingImportData else { return }
        pendingImportData = nil
        do {
            try settings.importConfiguration(from: data)
        } catch {
            transferError = error.localizedDescription
        }
    }

    private func refreshDNDPermission() {
        guard settings.disableDuringDND else {
            dndHasFullDiskAccess = true
            return
        }
        dndHasFullDiskAccess = DoNotDisturbChecker.hasFullDiskAccess
    }

    private func refreshLaunchApprovalState() {
        launchRequiresApproval = settings.launchAtLogin && LaunchAtLoginHelper.requiresApproval
    }

    private func openFullDiskAccessSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func canTestPopup(_ mapping: WebhookMapping) -> Bool {
        mapping.hasStreamSource
    }

    @ViewBuilder
    private func protectControls(_ mapping: Binding<WebhookMapping>) -> some View {
        cameraPicker(mapping)
        if let id = mapping.wrappedValue.protectCameraId,
           let cam = protect.cameras.first(where: { $0.id == id }) {
            LabeledContent("Auslöser") {
                TriggerChips(camera: cam, selection: mapping.triggers)
            }
        }
        advancedOptions(mapping)
    }

    private func cameraPicker(_ mapping: Binding<WebhookMapping>) -> some View {
        let selectedId = mapping.wrappedValue.protectCameraId
        let isUnknown = selectedId != nil && !protect.cameras.contains(where: { $0.id == selectedId })
        return Picker("Kamera", selection: mapping.protectCameraId) {
            Text("Keine (nur Webhook)").tag(String?.none)
            ForEach(protect.cameras) { cam in
                Text(cam.name).tag(Optional(cam.id))
            }
            if isUnknown {
                Text("Unbekannte Kamera").tag(selectedId)
            }
        }
        .onChange(of: selectedId) { newId in
            guard mapping.wrappedValue.triggers.isEmpty,
                  let newId,
                  let cam = protect.cameras.first(where: { $0.id == newId }) else { return }
            let defaults: Set<TriggerKind> = [.ring, .person]
            mapping.wrappedValue.triggers = defaults.intersection(cam.supportedTriggers)
        }
    }

    private func advancedOptions(_ mapping: Binding<WebhookMapping>) -> some View {
        DisclosureGroup("Erweitert") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Zusätzlich per Webhook auslösen", isOn: mapping.webhookTriggerEnabled)
                if mapping.wrappedValue.webhookTriggerEnabled {
                    TextField("Webhook-Slug (z. B. front-door)", text: mapping.webhookId)
                        .textFieldStyle(.roundedBorder)
                }
                TextField("RTSP URL", text: mapping.rtspsURL, prompt: Text("automatisch aus Protect"))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: mapping.wrappedValue.rtspsURL) { newValue in
                        let normalized = StreamURL.normalizedRTSP(newValue)
                        if normalized != newValue {
                            mapping.wrappedValue.rtspsURL = normalized
                        }
                    }
                if let warning = streamURLWarning(for: mapping.wrappedValue.rtspsURL) {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
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

/// Edits a camera's action buttons (title, webhook URL, method, optional token).
private struct CameraActionsEditor: View {
    @Binding var actions: [CameraAction]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aktions-Buttons")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach($actions) { $action in
                CameraActionRow(action: $action) {
                    actions.removeAll { $0.id == action.id }
                }
            }

            HStack {
                Button("Aktions-Button hinzufügen") {
                    actions.append(CameraAction())
                }
                .disabled(actions.count >= WebhookMapping.maxActions)
                Text("max. \(WebhookMapping.maxActions) pro Kamera")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

private struct CameraActionRow: View {
    @Binding var action: CameraAction
    let onRemove: () -> Void

    private enum TestState: Equatable {
        case idle, running, succeeded, failed(String)
    }

    @State private var testState: TestState = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Titel (z. B. Tür öffnen)", text: $action.title)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $action.method) {
                    ForEach(CameraAction.Method.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            TextField("Webhook-URL", text: $action.url, prompt: Text("https://…"))
                .textFieldStyle(.roundedBorder)
            SecureField("Bearer-Token (optional)", text: $action.bearerToken)
                .textFieldStyle(.roundedBorder)

            if let warning = urlWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                testStatusView
                Spacer()
                Button("Testen") { runTest() }
                    .disabled(!action.isConfigured || testState == .running)
                Button("Entfernen", role: .destructive, action: onRemove)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
    }

    @ViewBuilder
    private var testStatusView: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .running:
            ProgressView().controlSize(.small)
        case .succeeded:
            Label("Erfolgreich", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private var urlWarning: String? {
        let trimmed = action.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, action.requestURL == nil else { return nil }
        return "Bitte eine gültige http:// oder https:// URL eintragen."
    }

    private func runTest() {
        let snapshot = action
        testState = .running
        Task {
            do {
                try await CameraActionService.trigger(snapshot)
                testState = .succeeded
            } catch {
                testState = .failed(error.localizedDescription)
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if testState != .running { testState = .idle }
        }
    }
}
