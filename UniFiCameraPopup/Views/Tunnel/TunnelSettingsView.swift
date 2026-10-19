import AppCore
import ProtectKit
import SwiftUI

/// Content of the settings tab „Unterwegs“ (Vorlage S6, docs/design/einstellungen-unterwegs.md).
struct TunnelSettingsView: View {
    @ObservedObject private var store = TunnelStore.shared
    @ObservedObject private var router = ConnectionRouter.shared
    @ObservedObject private var tunnel = TunnelController.shared
    @StateObject private var replaceAnchor = ViewAnchor()
    @State private var feedback: ImportFeedback?
    @State private var showGuide = false
    @State private var confirmRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.hasConfiguration {
                statusCard
                details
            } else {
                emptyState
            }
            if let feedback {
                ImportFeedbackView(feedback: feedback)
            }
            if let outcome = router.testOutcome {
                Text(outcome.message)
                    .font(.system(size: 12))
                    .foregroundStyle(outcome == .ok ? Tokens.ok.color : Color(nsColor: .systemOrange))
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .foregroundStyle(Tokens.fg.color)
        .padding(.horizontal, 40)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showGuide) { WireGuardGuideView() }
        .confirmationDialog("Tunnel entfernen?", isPresented: $confirmRemove) {
            Button("Entfernen", role: .destructive) {
                router.removeTunnel()
                feedback = nil
            }
        } message: {
            Text("Die WireGuard-Datei wird aus dem Schlüsselbund gelöscht. Unterwegs ist die Konsole dann nicht mehr erreichbar.")
        }
    }

    private var phase: TunnelPhase {
        #if DEBUG
        if SnapshotRenderer.isActive, let sample = SnapshotRenderer.tunnelPhase { return sample }
        #endif
        return TunnelPhase.from(mode: store.mode, route: router.route, state: tunnel.state)
    }

    /// 1. Statusfläche: Abstand 14, Innenabstand 14/16, Radius 12, `accSoft`.
    private var statusCard: some View {
        let text = TunnelText.status(phase)
        return HStack(spacing: 14) {
            TemplateIcon.shieldCheck.image(size: 20)
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Tokens.accent.color))
            VStack(alignment: .leading, spacing: 2) {
                Text(text.title).font(.system(size: 14, weight: .bold))
                Text(text.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.muted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(router.isTesting ? "Teste …" : "Jetzt testen") {
                Task { await router.testNow() }
            }
            .buttonStyle(FieldButtonStyle(fontSize: 12, vertical: 4, horizontal: 12))
            .disabled(router.isTesting)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Tokens.accSoft.color))
    }

    /// 2. Karte Radius 10, Zeilen 10/14, Beschriftung 140 breit.
    private var details: some View {
        Card {
            FixedLabelRow(title: "Konfiguration", width: 140, vertical: 10, horizontal: 14) {
                Text(store.fileName ?? "–")
                    .foregroundStyle(Tokens.muted.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Ersetzen …") {
                    guard let view = replaceAnchor.view else { return }
                    MenuPresenter.popUp(titles: WireGuardImport.menuTitles, selectedIndex: nil, in: view) { index in
                        Task { if let result = await WireGuardImport.run(menuIndex: index) { feedback = result } }
                    }
                }
                .buttonStyle(FieldButtonStyle())
                .background(AnchorView(anchor: replaceAnchor))
            }
            CardDivider()
            FixedLabelRow(title: "Gegenstelle", width: 140, vertical: 10, horizontal: 14) {
                Text(store.summary?.endpoint ?? "–")
                    .foregroundStyle(Tokens.muted.color)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            CardDivider()
            FixedLabelRow(title: "Letzte Verbindung", width: 140, vertical: 10, horizontal: 14) {
                Text(lastConnectionText)
                    .foregroundStyle(Tokens.muted.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            CardDivider()
            CardRow(title: "Tunnel verwenden") {
                PopUpField(
                    selection: Binding(
                        get: { store.mode },
                        set: { store.mode = $0; router.configurationChanged() }
                    ),
                    options: TunnelMode.allCases.map { (value: $0, title: $0.label) }
                )
            }
        }
    }

    private var lastConnectionText: String {
        guard let last = store.lastConnection else { return "noch nie" }
        return TunnelText.lastConnection(dayAndTime: DisplayText.dayAndTime(last.date, now: Date()), via: last.via)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Noch nicht eingerichtet").font(.system(size: 14, weight: .bold))
                Text("Lege die WireGuard-Datei deines Gateways hier ab. Die App nutzt den Tunnel nur für sich.")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.muted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            WireGuardDropZone { feedback = $0 }
        }
    }

    /// 3. Zeile verteilt: Anleitung (12, `accText`) · Tunnel entfernen (12, `muted`).
    private var footer: some View {
        HStack {
            Button("Anleitung: WireGuard auf dem UniFi-Gateway einrichten") { showGuide = true }
                .buttonStyle(LinkButtonStyle())
            Spacer()
            if store.hasConfiguration {
                Button("Tunnel entfernen") { confirmRemove = true }
                    .buttonStyle(LinkButtonStyle(color: Tokens.muted))
            }
        }
    }
}
