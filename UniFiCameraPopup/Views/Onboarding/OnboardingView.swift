import AppCore
import ProtectKit
import SwiftUI

@MainActor
final class OnboardingModel: ObservableObject {
    enum Step: Int, CaseIterable { case welcome, console, key, cameras, triggers, travel }

    @Published var step: Step = .welcome
    @Published var consoles: [DiscoveredConsole] = []
    @Published var isScanning = false
    @Published var selectedHost = ""
    @Published var manualHost = ""
    @Published var apiKey = ""
    @Published var checking = false
    @Published var keyError: String?
    @Published var cameras: [ProtectCamera] = []
    @Published var selectedCameraIds: Set<String> = []
    @Published var triggers: [String: Set<TriggerKind>] = [:]
    @Published var triggerTab: String = ""
    var onFinish: () -> Void = {}

    @Published var certificateChanged = false
    private var capturedFingerprint: String?
    /// Fingerprint the user explicitly confirmed (certificate change or a different console);
    /// the key is only sent pinned to it, and only to the canonical host it was confirmed for.
    private var confirmedFingerprint: String?
    private var confirmedHost: String?
    @Published var pendingFingerprint: String?
    /// Why the trust alert is shown: the known console's certificate changed, or the address
    /// points at another console than the one whose certificate is pinned.
    @Published var pendingIsDifferentConsole = false
    @Published var probing = false
    /// Bumped by every `checkKey()`/probe so a late answer for an earlier attempt is dropped.
    private var generation = 0

    var host: String {
        let manual = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return manual.isEmpty ? selectedHost.trimmingCharacters(in: .whitespacesAndNewlines) : manual
    }

    /// One spelling per console (`https://H/`, `H:443` and `h` are the same console).
    var canonicalHost: String? { ProtectClient.canonicalHost(host) }

    func resetTrust() {
        confirmedFingerprint = nil
        confirmedHost = nil
        pendingFingerprint = nil
        pendingIsDifferentConsole = false
        certificateChanged = false
    }

    /// Phase 1 of re-trust: read the presented fingerprint without sending the API key.
    func probeNewCertificate(differentConsole: Bool = false) {
        generation += 1
        let attempt = generation
        let probeHost = canonicalHost
        probing = true
        keyError = nil
        Task {
            let result: Result<String, Error>
            do {
                // Away: through the tunnel (no key is sent, only the certificate is read).
                guard let dialHost = await ConnectionRouter.shared.resolveAPIHost(for: host) else {
                    throw TunnelRouteError.apiUnreachable
                }
                result = .success(try await ProtectClient.probeFingerprint(host: dialHost))
            } catch {
                result = .failure(error)
            }
            guard attempt == generation else { return }  // a newer attempt owns the state
            probing = false
            guard canonicalHost == probeHost else { return }
            switch result {
            case .success(let fingerprint):
                pendingIsDifferentConsole = differentConsole
                pendingFingerprint = fingerprint
            case .failure(let error):
                keyError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Phase 2: the user confirmed the fingerprint; connect pinned to it.
    func confirmPendingFingerprint() {
        guard let pending = pendingFingerprint else { return }
        pendingFingerprint = nil
        confirmedFingerprint = pending
        confirmedHost = canonicalHost
        checkKey()
    }

    func scan() {
        isScanning = true
        Task {
            let found = await ConsoleDiscovery().scan(duration: 3)
            consoles = found
            if selectedHost.isEmpty, let first = found.first { selectedHost = first.ip }
            isScanning = false
        }
    }

    func checkKey() {
        let settings = SettingsStore.shared
        let requestHost = canonicalHost
        let confirmed = confirmedHost != nil && confirmedHost == requestHost ? confirmedFingerprint : nil
        let samePinnedHost = requestHost != nil && requestHost == ProtectClient.canonicalHost(settings.protectHost)
        // While any console is pinned, a different address is never trusted on first use:
        // confirm the other console's fingerprint first (same alert as a certificate change).
        if confirmed == nil, settings.protectCertificateFingerprint != nil, !samePinnedHost, requestHost != nil {
            certificateChanged = false
            probeNewCertificate(differentConsole: true)
            return
        }
        generation += 1
        let attempt = generation
        checking = true
        keyError = nil
        certificateChanged = false
        capturedFingerprint = confirmed
        let pin = confirmed ?? (samePinnedHost ? settings.protectCertificateFingerprint : nil)
        let dialHost = host
        let key = apiKey
        Task {
            defer {
                // A newer attempt owns `checking`; otherwise this attempt is over on every path.
                if attempt == generation { checking = false }
            }
            // Away: through the tunnel, never the direct address as a fallback.
            guard let apiHost = await ConnectionRouter.shared.resolveAPIHost(for: dialHost) else {
                if attempt == generation { keyError = TunnelRouteError.apiUnreachable.errorDescription }
                return
            }
            // Through the tunnel the key only goes out pinned to a known or confirmed certificate.
            if apiHost != dialHost, pin?.isEmpty ?? true {
                if attempt == generation { keyError = TunnelRouteError.pinRequired.errorDescription }
                return
            }
            let client = makeKeyCheckClient(host: apiHost, apiKey: key, pin: pin, attempt: attempt)
            defer { client.invalidate() }
            do {
                _ = try await client.metaInfo()
                let cams = try await client.cameras()
                // Drop the answer if a newer attempt started or the address changed meanwhile.
                guard attempt == generation, canonicalHost == requestHost else { return }
                cameras = cams
                let existing = settings.mappings
                let configured = Set(existing.filter { $0.protectCameraId != nil && !$0.triggers.isEmpty }.compactMap(\.protectCameraId))
                let hasProtectMappings = existing.contains { $0.protectCameraId != nil }
                if hasProtectMappings {
                    selectedCameraIds = Set(cams.map(\.id)).intersection(configured)
                } else {
                    selectedCameraIds = Set(cams.filter(\.isConnected).map(\.id))
                }
                for cam in cams {
                    if let mapping = existing.first(where: { $0.protectCameraId == cam.id }) {
                        triggers[cam.id] = mapping.triggers
                    } else {
                        triggers[cam.id] = cam.enabledTriggers.intersection([
                            .ring, .person, .package, .vehicle, .animal, .personLine, .vehicleLine, .animalLine,
                        ])
                    }
                }
                triggerTab = cams.first(where: { selectedCameraIds.contains($0.id) })?.id ?? ""
                step = .cameras
            } catch {
                guard attempt == generation, canonicalHost == requestHost else { return }
                if case ProtectError.certificateChanged = error { certificateChanged = true }
                keyError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Client for `checkKey`; captures the model weakly (built outside the attempt's Task).
    private func makeKeyCheckClient(host: String, apiKey: String, pin: String?, attempt: Int) -> ProtectClient {
        ProtectClient(host: host, apiKey: apiKey, pinnedFingerprint: pin, onNewFingerprint: { [weak self] fp in
            Task { @MainActor in
                guard let self, self.generation == attempt else { return }
                self.capturedFingerprint = fp
            }
        })
    }

    private static func sameLabel(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(b.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    func finish() {
        let settings = SettingsStore.shared
        // Order matters: setting a different host clears the pinned fingerprint.
        settings.protectHost = canonicalHost ?? host
        if let name = consoles.first(where: { $0.ip == host })?.displayName {
            settings.protectConsoleName = name
        }
        if let capturedFingerprint { settings.protectCertificateFingerprint = capturedFingerprint }
        settings.protectAPIKey = apiKey
        for cam in cameras where selectedCameraIds.contains(cam.id) {
            if let index = settings.mappings.firstIndex(where: { $0.protectCameraId == cam.id }) {
                settings.mappings[index].triggers = triggers[cam.id] ?? []
            } else if let index = settings.mappings.firstIndex(where: {
                $0.protectCameraId == nil && Self.sameLabel($0.label, cam.name)
            }) {
                // Adopt the existing webhook entry for this camera instead of adding a second
                // one: popups are keyed by entry, so webhook and Protect events then share one
                // popup. Everything else (webhook trigger, hotkey, zoom, actions) stays as is.
                settings.mappings[index].protectCameraId = cam.id
                settings.mappings[index].triggers = triggers[cam.id] ?? [.ring, .person]
            } else {
                var mapping = WebhookMapping(rtspsURL: "", label: cam.name)
                mapping.protectCameraId = cam.id
                mapping.triggers = triggers[cam.id] ?? [.ring, .person]
                settings.mappings.append(mapping)
            }
        }
        for index in settings.mappings.indices {
            if let id = settings.mappings[index].protectCameraId, !selectedCameraIds.contains(id) {
                settings.mappings[index].triggers = []
            }
        }
        // Route for the saved address, not the previous one (would keep a stale tunnel).
        ConnectionRouter.shared.consoleChanged()
        ProtectSession.shared.reconnect()
        onFinish()
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 12) {
            switch model.step {
            case .welcome: welcome
            case .console: console
            case .key: key
            case .cameras: camerasStep
            case .triggers: triggersStep
            case .travel: OnboardingTunnelStep(onLater: { model.finish() }, onDone: { model.finish() })
            }
            dots
        }
        .padding(.horizontal, 44)
        .padding(.top, 28)
        .padding(.bottom, 22)
        .frame(width: 560, height: 420)
        .alert("Neuem Zertifikat vertrauen?", isPresented: Binding(
            get: { model.pendingFingerprint != nil },
            set: { if !$0 { model.pendingFingerprint = nil } }
        )) {
            Button("Vertrauen") { model.confirmPendingFingerprint() }
            Button("Abbrechen", role: .cancel) { model.pendingFingerprint = nil }
        } message: {
            if model.pendingIsDifferentConsole {
                Text("„\(model.canonicalHost ?? model.host)“ ist eine andere Konsole als die bisher eingerichtete. Bestätige nur, wenn das wirklich deine Konsole ist – erst dann wird dein API-Schlüssel dorthin gesendet. Fingerabdruck der neuen Konsole:\n\n\(model.pendingFingerprint ?? "")")
            } else {
                Text("Das Zertifikat deiner Konsole hat sich geändert. Bestätige nur, wenn du es selbst geändert hast (z. B. nach einem Konsolen-Update). Neuer Fingerabdruck:\n\n\(model.pendingFingerprint ?? "")")
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingModel.Step.allCases, id: \.self) { s in
                Circle()
                    // docs/design/einrichtung-unterwegs.md 9: current `accent`, others `dotOff`.
                    .fill(s == model.step ? Tokens.accent.color : Tokens.dotOff.color)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Schritt \(model.step.rawValue + 1) von \(OnboardingModel.Step.allCases.count)")
    }

    private func header(_ symbol: String, _ title: String, _ text: String?) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Color.accentColor.opacity(0.14)))
            Text(title).font(.title3.bold()).multilineTextAlignment(.center)
            if let text {
                Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func primary(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(width: 196) }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(disabled)
    }

    private var welcome: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.fill")
                .font(.system(size: 38))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.accentColor))
            Text("Willkommen bei Camera Popup").font(.title2.bold())
            Text("Wenn jemand klingelt oder eine Kamera etwas erkennt, siehst du es sofort – und kannst direkt antworten.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            primary("Weiter") { model.step = .console; model.scan() }
        }
    }

    private var console: some View {
        VStack(spacing: 12) {
            header("server.rack", model.consoles.isEmpty ? "Wir suchen deine Konsole …" : "Wir haben deine Konsole gefunden", nil)
            VStack(spacing: 6) {
                ForEach(model.consoles, id: \.ip) { c in
                    Button { model.selectedHost = c.ip; model.manualHost = "" } label: {
                        HStack {
                            Text(c.displayName).fontWeight(model.selectedHost == c.ip ? .semibold : .regular)
                            Spacer()
                            Text(c.ip).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(model.selectedHost == c.ip && model.manualHost.isEmpty ? Color.accentColor : Color.secondary.opacity(0.3),
                                          lineWidth: model.selectedHost == c.ip && model.manualHost.isEmpty ? 2 : 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if model.isScanning { ProgressView().controlSize(.small) }
                TextField("Oder Adresse eingeben, z. B. 192.168.1.1", text: $model.manualHost)
                    .textFieldStyle(.roundedBorder)
            }
            Spacer()
            HStack {
                Button("Zurück") { model.step = .welcome }.controlSize(.large)
                primary("Diese verwenden", disabled: model.host.isEmpty) { model.resetTrust(); model.step = .key }
            }
        }
    }

    private var key: some View {
        VStack(spacing: 11) {
            header("key.fill", "Ein Schlüssel für die App",
                   "Erzeuge in deiner Konsole unter Einstellungen einen API-Schlüssel – der Bereich heißt meist „API“ oder „Integrationen“ – und füge ihn hier ein.")
            SecureField("API-Schlüssel", text: $model.apiKey)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.checkKey() }
            if let error = model.keyError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red)
            }
            if model.certificateChanged {
                Button(model.probing ? "Prüfe …" : "Neuem Zertifikat vertrauen") { model.probeNewCertificate() }
                    .controlSize(.large)
                    .disabled(model.checking || model.probing)
            }
            if let consoleURL = URL(string: "https://\(model.host)"), consoleURL.host != nil {
                Link("Konsole im Browser öffnen", destination: consoleURL)
                    .font(.callout)
            }
            Spacer()
            HStack {
                Button("Zurück") { model.step = .console }
                    .controlSize(.large)
                    .disabled(model.checking || model.probing)
                primary(model.checking || model.probing ? "Prüfe …" : "Verbinden",
                        disabled: model.apiKey.isEmpty || model.checking || model.probing) { model.checkKey() }
            }
        }
    }

    private var camerasStep: some View {
        VStack(spacing: 12) {
            Text("Welche Kameras sollen sich melden?").font(.title3.bold())
            if model.cameras.isEmpty {
                Spacer()
                Text("Keine Kameras gefunden. Prüfe, ob Protect läuft und der Schlüssel Zugriff auf Kameras hat.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(model.checking ? "Lade …" : "Erneut laden") { model.checkKey() }
                    .controlSize(.large).disabled(model.checking)
                Spacer()
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                    ForEach(model.cameras) { cam in
                        let on = model.selectedCameraIds.contains(cam.id)
                        Button {
                            if on { model.selectedCameraIds.remove(cam.id) } else { model.selectedCameraIds.insert(cam.id) }
                        } label: {
                            VStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.black.opacity(0.75))
                                    .frame(height: 70)
                                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 3))
                                    .overlay(alignment: .bottomTrailing) {
                                        if on {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, Color.accentColor).padding(5)
                                        }
                                    }
                                    .opacity(cam.isConnected ? 1 : 0.5)
                                Text(cam.name).font(.callout.weight(.semibold)).lineLimit(1)
                                Text(cam.hasSpeaker ? "mit Lautsprecher" : "nur Bild").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            HStack {
                Button("Zurück") { model.step = .key }.controlSize(.large)
                primary("Weiter mit \(model.selectedCameraIds.count) Kameras", disabled: model.selectedCameraIds.isEmpty) {
                    model.triggerTab = model.cameras.first { model.selectedCameraIds.contains($0.id) }?.id ?? ""
                    model.step = .triggers
                }
            }
        }
    }

    private var triggersStep: some View {
        let selected = model.cameras.filter { model.selectedCameraIds.contains($0.id) }
        let current = selected.first { $0.id == model.triggerTab } ?? selected.first
        return VStack(spacing: 14) {
            Text("Wann soll sich welche Kamera melden?").font(.title3.bold())
            cameraSwitcher(selected, current: current)
            if let cam = current {
                Text("Tippe an, was bei \(cam.name) ein Popup auslöst. Zu sehen ist, was in Protect für diese Kamera eingeschaltet ist.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                TriggerChips(camera: cam, selection: Binding(
                    get: { model.triggers[cam.id] ?? [] },
                    set: { model.triggers[cam.id] = $0 }
                ))
            }
            Spacer()
            HStack {
                Button("Zurück") { model.step = .cameras }.controlSize(.large)
                primary("Weiter") { model.step = .travel }
            }
        }
    }
}

extension OnboardingView {
    /// Segmented tabs while every name fits; beyond four cameras a menu with
    /// previous/next arrows, so any number of cameras stays reachable.
    @ViewBuilder
    fileprivate func cameraSwitcher(_ selected: [ProtectCamera], current: ProtectCamera?) -> some View {
        if selected.count <= 4 {
            Picker("Kamera", selection: $model.triggerTab) {
                ForEach(selected) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } else {
            let index = current.flatMap { cam in selected.firstIndex { $0.id == cam.id } } ?? 0
            HStack(spacing: 8) {
                Button {
                    model.triggerTab = selected[index - 1].id
                } label: { Image(systemName: "chevron.left") }
                .disabled(index == 0)
                .accessibilityLabel("Vorherige Kamera")
                Picker("Kamera", selection: $model.triggerTab) {
                    ForEach(selected) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 260)
                Button {
                    model.triggerTab = selected[index + 1].id
                } label: { Image(systemName: "chevron.right") }
                .disabled(index >= selected.count - 1)
                .accessibilityLabel("Nächste Kamera")
                Text("\(index + 1) von \(selected.count)")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}

/// Toggle chips for trigger kinds; shared with the settings.
/// `.regular`: onboarding (13 pt, on 7/14, off 6/13, centered, gap 8).
/// `.small`: Einstellungen › Kameras (12 pt, on 4/11, off 3/10, leading, gap 6).
struct TriggerChips: View {
    enum Size {
        case regular
        case small
    }

    let camera: ProtectCamera
    @Binding var selection: Set<TriggerKind>
    var size: Size = .regular

    var body: some View {
        // Only what is switched on in Protect for this camera; a choice for a kind switched off
        // there stays stored (hidden) and counts again once it is switched back on.
        let chips = TriggerKind.chips(enabled: camera.enabledTriggers)
        VStack(alignment: size == .regular ? .center : .leading, spacing: size == .regular ? 10 : 7) {
            row(chips.detections)
            if !chips.lines.isEmpty {
                Text("Linie überquert – nur wenn in Protect Linien eingerichtet sind:")
                    .font(.system(size: size == .regular ? 12 : 11))
                    .foregroundStyle(Tokens.muted.color)
                row(chips.lines)
            }
        }
    }

    private func row(_ kinds: [TriggerKind]) -> some View {
        FlowLayout(spacing: size == .regular ? 8 : 6, alignment: size == .regular ? .center : .leading) {
            ForEach(kinds, id: \.self) { kind in
                let isOn = selection.contains(kind)
                Button {
                    if isOn { selection.remove(kind) } else { selection.insert(kind) }
                } label: {
                    label(kind.chipLabel, isOn: isOn)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kind.label)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    @ViewBuilder
    private func label(_ text: String, isOn: Bool) -> some View {
        let fontSize: CGFloat = size == .regular ? 13 : 12
        if isOn {
            Text(text)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.vertical, size == .regular ? 7 : 4)
                .padding(.horizontal, size == .regular ? 14 : 11)
                .background(Capsule().fill(Tokens.accent.color))
        } else {
            Text(text)
                .font(.system(size: fontSize))
                .foregroundStyle(Tokens.fg.color)
                .padding(.vertical, size == .regular ? 6 : 3)
                .padding(.horizontal, size == .regular ? 13 : 10)
                .background(Capsule().fill((size == .regular ? Tokens.mainChipOff : Tokens.chipOff).color))
                .overlay(Capsule().strokeBorder(Tokens.chipBorder.color, lineWidth: 1))
        }
    }
}

/// Minimal wrapping layout (macOS 13+).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var alignment: HorizontalAlignment = .center

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = alignment == .leading ? bounds.minX : bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if rows[rows.count - 1].width + size.width > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
