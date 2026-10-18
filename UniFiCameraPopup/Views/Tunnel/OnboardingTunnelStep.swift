import AppCore
import SwiftUI

/// Einrichtung, Schritt 6 „Auch unterwegs?“ (Vorlage Main 6). Abstand 11 wie in der Vorlage.
struct OnboardingTunnelStep: View {
    let onLater: () -> Void
    let onDone: () -> Void
    @ObservedObject private var store = TunnelStore.shared
    @State private var feedback: ImportFeedback?
    @State private var showGuide = false

    init(onLater: @escaping () -> Void, onDone: @escaping () -> Void) {
        self.onLater = onLater
        self.onDone = onDone
        #if DEBUG
        _feedback = State(initialValue: SnapshotRenderer.isActive ? SnapshotRenderer.tunnelStepFeedback : nil)
        #endif
    }

    var body: some View {
        VStack(spacing: 11) {
            TemplateIcon.tabRemote.image(size: 30)
                .foregroundStyle(Tokens.accText.color)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Tokens.accSoft.color))
            Text("Auch unterwegs?")
                .font(.system(size: 20, weight: .bold))
            Text("Lege auf deinem UniFi-Gateway einen WireGuard-Server an, füge einen Client für diesen Mac hinzu und lade dessen Datei herunter. Die App nutzt den Tunnel nur für sich.")
                .font(.system(size: 12))
                .lineSpacing(3)
                .foregroundStyle(Tokens.muted.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            WireGuardDropZone { feedback = $0 }
            if let feedback {
                ImportFeedbackView(feedback: feedback)
            } else if let endpoint = store.summary?.endpoint {
                ImportFeedbackView(feedback: .imported(endpoint: endpoint, warning: nil))
            }
            Button("Ausführliche Anleitung öffnen") { showGuide = true }
                .buttonStyle(LinkButtonStyle())
            Spacer()
            HStack(spacing: 10) {
                Button(action: onLater) { Text("Später").frame(width: 126) }
                    .controlSize(.large)
                Button(action: onDone) { Text("Fertig").frame(width: 126) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .sheet(isPresented: $showGuide) { WireGuardGuideView() }
    }
}
