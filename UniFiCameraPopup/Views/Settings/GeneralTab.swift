import AppCore
import AppKit
import ProtectKit
import SwiftUI
import UniformTypeIdentifiers

/// Einstellungen › Allgemein (docs/design/einstellungen-allgemein.md).
struct GeneralTab: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var webSocketClient: WebSocketClient
    @EnvironmentObject private var protectEvents: ProtectEventService
    @ObservedObject private var protect = ProtectSession.shared
    @ObservedObject private var router = ConnectionRouter.shared

    @State private var advancedExpanded = false
    @State private var dndHasFullDiskAccess = true
    @State private var launchRequiresApproval = false
    @State private var pendingImportData: Data?
    @State private var transferError: String?
    @State private var probingCertificate = false
    @State private var trustProbeError: String?
    @State private var pendingFingerprint: String?
    @State private var showRegenerateConfirm = false
    @State private var copiedWebhookURL = false
    @State private var copiedBearerToken = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                connectionCard
                preferencesCard
                muteSection
                footer
                if advancedExpanded {
                    advanced
                }
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 40)
        }
        .onAppear {
            refreshDNDPermission()
            refreshLaunchApprovalState()
        }
        .onChange(of: settings.disableDuringDND) { _ in refreshDNDPermission() }
        .onChange(of: settings.launchAtLogin) { _ in refreshLaunchApprovalState() }
        .alert("Neuem Zertifikat vertrauen?", isPresented: Binding(
            get: { pendingFingerprint != nil },
            set: { if !$0 { pendingFingerprint = nil } }
        )) {
            Button("Vertrauen") { confirmPendingFingerprint() }
            Button("Abbrechen", role: .cancel) { pendingFingerprint = nil }
        } message: {
            Text("Das Zertifikat deiner Konsole hat sich geändert. Bestätige nur, wenn du es selbst geändert hast (z. B. nach einem Konsolen-Update). Neuer Fingerabdruck:\n\n\(pendingFingerprint ?? "")")
        }
        .alert("Neue ID generieren?", isPresented: $showRegenerateConfirm) {
            Button("Abbrechen", role: .cancel) {}
            Button("Neue ID", role: .destructive) { settings.regenerateInstallationId() }
        } message: {
            Text("Die Webhook-Adressen ändern sich. Du musst die Webhooks in UniFi Protect anschließend neu eintragen.")
        }
        .alert("Konfiguration importieren?", isPresented: Binding(
            get: { pendingImportData != nil },
            set: { if !$0 { pendingImportData = nil } }
        )) {
            Button("Abbrechen", role: .cancel) { pendingImportData = nil }
            Button("Importieren", role: .destructive) { confirmImport() }
        } message: {
            Text("Die aktuelle Konfiguration wird vollständig ersetzt – einschließlich der eindeutigen ID und aller Kameras.")
        }
        .alert("Import fehlgeschlagen", isPresented: Binding(
            get: { transferError != nil },
            set: { if !$0 { transferError = nil } }
        ), presenting: transferError) { _ in
            Button("OK", role: .cancel) { transferError = nil }
        } message: { message in
            Text(message)
        }
    }

    // MARK: Konsole

    private var connectionCard: some View {
        Card {
            CardRow(title: "Konsole", vertical: 11) {
                HStack(spacing: 6) {
                    Circle().fill(consoleDotColor).frame(width: 8, height: 8)
                    Text(consoleText).lineLimit(1).truncationMode(.middle)
                }
                .foregroundStyle(Tokens.muted.color)
                Button(settings.protectHost.isEmpty ? "Einrichten …" : "Ändern …") {
                    OnboardingWindow.show(startAt: settings.protectHost.isEmpty ? .welcome : .console)
                }
                .buttonStyle(FieldButtonStyle())
            }
            CardDivider()
            CardRow(title: "API-Schlüssel", vertical: 11) {
                Text(settings.protectAPIKey.isEmpty ? "nicht hinterlegt" : "im Schlüsselbund")
                    .foregroundStyle(Tokens.muted.color)
                Button("Ersetzen …") { OnboardingWindow.show(startAt: .key) }
                    .buttonStyle(FieldButtonStyle())
                    .disabled(settings.protectHost.isEmpty)
            }
            if let error = protect.lastError {
                CardDivider()
                connectionErrorRow(error)
            }
        }
    }

    private var consoleText: String {
        let host = settings.protectHost
        guard !host.isEmpty else { return "nicht eingerichtet" }
        if let name = settings.protectConsoleName, !name.isEmpty {
            return "\(name) · \(host)"
        }
        return host
    }

    private var consoleDotColor: Color {
        guard settings.isProtectConfigured else { return Tokens.toggleOff.color }
        if protect.lastError != nil { return Color(nsColor: .systemOrange) }
        switch protectEvents.status {
        case .connected: return Tokens.statusGreen.color
        case .connecting: return Color(nsColor: .systemOrange)
        case .disconnected, .outdated: return Color(nsColor: .systemRed)
        }
    }

    private func connectionErrorRow(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(error)
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: .systemOrange))
                .fixedSize(horizontal: false, vertical: true)
            // Only once the route is settled: before that the certificate may be a foreign
            // device's on the current network, which must never be offered for trust.
            if error == ProtectError.certificateChanged.errorDescription, router.isRouteSettled {
                HStack(spacing: 8) {
                    Button(probingCertificate ? "Prüfe …" : "Neuem Zertifikat vertrauen") {
                        probeNewCertificate()
                    }
                    .buttonStyle(FieldButtonStyle())
                    .disabled(probingCertificate)
                    if let trustProbeError {
                        Text(trustProbeError)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(nsColor: .systemRed))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
    }

    // MARK: Darstellung und Verhalten

    private var preferencesCard: some View {
        Card {
            CardRow(title: "Erscheinungsbild") {
                TokenSegmented(
                    selection: $settings.appearance,
                    options: AppearanceMode.allCases.map { (value: $0, title: $0.label) }
                )
            }
            CardDivider()
            CardRow(title: "Popup-Position") {
                PopUpField(
                    selection: $settings.defaultPosition,
                    options: PopupPosition.allCases.map { (value: $0, title: $0.label) }
                )
            }
            CardDivider()
            CardToggleRow(title: "Im Fokus-Modus keine Popups", isOn: $settings.disableDuringDND)
            if settings.disableDuringDND && !dndHasFullDiskAccess {
                CardDivider()
                hintRow(
                    "Ohne „Festplattenvollzugriff“ kann der Fokus-Status nicht erkannt werden. Aktiviere „UniFi Camera Popup“ in der Liste und starte die App danach neu.",
                    button: "Festplattenvollzugriff öffnen",
                    action: openFullDiskAccessSettings
                )
            }
            CardDivider()
            CardToggleRow(title: "Bei Anmeldung starten", isOn: $settings.launchAtLogin)
            if launchRequiresApproval {
                CardDivider()
                hintRow(
                    "„UniFi Camera Popup“ muss in den Anmeldeobjekten freigegeben werden, sonst startet die App nicht automatisch.",
                    button: "Anmeldeobjekte öffnen",
                    action: LaunchAtLoginHelper.openLoginItemsSettings
                )
            }
        }
    }

    private func hintRow(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Tokens.muted.color)
                .fixedSize(horizontal: false, vertical: true)
            Button(button, action: action).buttonStyle(FieldButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }

    // MARK: Stummschalten

    private var muteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Stummschalten (Menüleiste)")
            Card {
                CardRow(title: "Kurz", vertical: 9) {
                    DurationField(duration: $settings.muteShort, accessibilityLabel: "Kurze Dauer")
                }
                CardDivider()
                CardRow(title: "Lang", vertical: 9) {
                    DurationField(duration: $settings.muteLong, accessibilityLabel: "Lange Dauer")
                }
            }
        }
    }

    // MARK: Export / Erweitert

    private var footer: some View {
        HStack(spacing: 8) {
            DisclosureButton(title: "Erweitert", expanded: $advancedExpanded)
            Spacer()
            Button("Konfiguration exportieren …") { exportConfiguration() }
                .buttonStyle(FieldButtonStyle(vertical: 4, horizontal: 12))
                .help("Die Exportdatei enthält deine eindeutige ID und die Bearer-Tokens der Buttons – teile sie nur mit deinen eigenen Geräten. Der API-Schlüssel bleibt im Schlüsselbund.")
            Button("Importieren …") { chooseConfigurationToImport() }
                .buttonStyle(FieldButtonStyle(vertical: 4, horizontal: 12))
        }
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Popup")
                Card {
                    CardRow(title: "Bildschirm") {
                        PopUpField(
                            selection: $settings.screenTarget,
                            options: ScreenTarget.allCases.map { (value: $0, title: $0.label) }
                        )
                    }
                    CardDivider()
                    sliderRow("Randabstand", value: $settings.edgeMargin, range: 0...120, step: 1,
                              text: "\(Int(settings.edgeMargin)) px")
                    CardDivider()
                    sliderRow("Automatisch schließen", value: $settings.autoCloseTimeout, range: 0...300, step: 5,
                              text: settings.autoCloseTimeout > 0 ? "\(Int(settings.autoCloseTimeout)) s" : "Aus")
                    CardDivider()
                    CardToggleRow(
                        title: "Alle aktiven Kameras zeigen",
                        subtitle: "Jede auslösende Kamera bekommt ein eigenes Popup, untereinander gestapelt. Ohne diese Option ersetzt eine neue Kamera das aktuelle Popup.",
                        isOn: $settings.showAllActiveCameras
                    )
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Updates")
                Card {
                    CardToggleRow(title: "Automatisch aktualisieren", isOn: $settings.autoUpdate)
                    CardDivider()
                    CardRow(title: "Version") {
                        Text("\(AppConfig.shortVersion) (\(AppConfig.buildNumber))")
                            .foregroundStyle(Tokens.muted.color)
                    }
                }
            }
            // Only needed while a camera is also triggered by webhook (Kameras › Erweitert).
            if settings.mappings.contains(where: \.webhookTriggerEnabled) {
                relaySection
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Hilfe")
                Card {
                    CardRow(title: "Anleitung und Problemlösung") {
                        Button("Hilfe öffnen") { AppActions.openHelp() }.buttonStyle(FieldButtonStyle())
                    }
                }
            }
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, text: String) -> some View {
        HStack(spacing: 10) {
            Text(title).frame(width: 170, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .controlSize(.small)
                .tint(Tokens.accent.color)
            Text(text)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Tokens.muted.color)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }

    private var relaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Webhooks (Relay-Server)")
            Card {
                FixedLabelRow(title: "Verbindung", width: 140, vertical: 10, horizontal: 14) {
                    HStack(spacing: 6) {
                        Circle().fill(relayDotColor).frame(width: 8, height: 8)
                        Text(webSocketClient.status == .outdated
                             ? "Veraltete App-Version. Bitte aktualisiere die App."
                             : webSocketClient.status.menuLabel)
                    }
                    .foregroundStyle(Tokens.muted.color)
                    Spacer(minLength: 0)
                }
                CardDivider()
                FixedLabelRow(title: "Eindeutige ID", width: 140, vertical: 10, horizontal: 14) {
                    monoText(settings.installationId)
                    Button("Neue ID …") { showRegenerateConfirm = true }.buttonStyle(FieldButtonStyle())
                }
                CardDivider()
                FixedLabelRow(title: "Webhook-Adresse", width: 140, vertical: 10, horizontal: 14) {
                    monoText(webhookURL)
                    Button(copiedWebhookURL ? "Kopiert" : "Kopieren") { copyWebhookURL() }.buttonStyle(FieldButtonStyle())
                }
                CardDivider()
                FixedLabelRow(title: "Bearer-Token", width: 140, vertical: 10, horizontal: 14) {
                    monoText(AppConfig.webhookToken)
                    Button(copiedBearerToken ? "Kopiert" : "Kopieren") { copyBearerToken() }.buttonStyle(FieldButtonStyle())
                }
                CardDivider()
                Text("\(AppConfig.webhookSlugPlaceholder) durch die Webhook-ID der Kamera ersetzen. Das Token gehört im UniFi Alarm Manager unter „Authentifizierung“ → „Bearer“.")
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.muted.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
            }
        }
    }

    private func monoText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Tokens.muted.color)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var relayDotColor: Color {
        switch webSocketClient.status {
        case .connected: return Tokens.statusGreen.color
        case .connecting: return Color(nsColor: .systemOrange)
        case .disconnected, .outdated: return Color(nsColor: .systemRed)
        }
    }

    // MARK: Actions (from the former SettingsView)

    private var webhookURL: String {
        AppConfig.webhookURL(installationId: settings.installationId)
    }

    private func copyWebhookURL() {
        copyToPasteboard(webhookURL)
        copiedWebhookURL = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedWebhookURL = false
        }
    }

    private func copyBearerToken() {
        copyToPasteboard(AppConfig.webhookToken)
        copiedBearerToken = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedBearerToken = false
        }
    }

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "unifi-camera-popup-config.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.exportedConfigurationData().write(to: url)
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
            // Host, key or pin may have changed; rebuild the client (and with it the event socket).
            ProtectSession.shared.reconnect()
        } catch {
            transferError = error.localizedDescription
        }
    }

    private func refreshDNDPermission() {
        dndHasFullDiskAccess = settings.disableDuringDND ? DoNotDisturbChecker.hasFullDiskAccess : true
    }

    private func refreshLaunchApprovalState() {
        launchRequiresApproval = settings.launchAtLogin && LaunchAtLoginHelper.requiresApproval
    }

    private func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Phase 1 of re-trust: read the presented fingerprint without sending the API key.
    private func probeNewCertificate() {
        probingCertificate = true
        trustProbeError = nil
        let host = settings.protectHost
        Task {
            defer { probingCertificate = false }
            do {
                // Away: through the tunnel (no key is sent, only the certificate is read).
                guard ConnectionRouter.shared.isRouteSettled,
                      let probeHost = await ConnectionRouter.shared.resolveAPIHost(for: host) else {
                    throw TunnelRouteError.apiUnreachable
                }
                pendingFingerprint = try await ProtectClient.probeFingerprint(host: probeHost)
            } catch {
                trustProbeError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Phase 2: only after explicit confirmation is the pin replaced; reconnect then connects pinned to it.
    private func confirmPendingFingerprint() {
        guard let fingerprint = pendingFingerprint else { return }
        pendingFingerprint = nil
        settings.protectCertificateFingerprint = fingerprint
        ProtectSession.shared.reconnect()
    }
}
