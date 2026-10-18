import ProtectKit
import SwiftUI

@MainActor
final class OnboardingModel: ObservableObject {
    enum Step: Int, CaseIterable { case welcome, console, key, cameras, triggers }

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
    private var trustNewCertificate = false

    var host: String {
        let manual = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return manual.isEmpty ? selectedHost.trimmingCharacters(in: .whitespacesAndNewlines) : manual
    }

    func resetTrust() { trustNewCertificate = false; certificateChanged = false }

    func scan() {
        isScanning = true
        Task {
            let found = await ConsoleDiscovery().scan(duration: 3)
            consoles = found
            if selectedHost.isEmpty, let first = found.first { selectedHost = first.ip }
            isScanning = false
        }
    }

    func checkKey(trustNew: Bool = false) {
        if trustNew { trustNewCertificate = true }
        checking = true
        keyError = nil
        certificateChanged = false
        capturedFingerprint = nil
        let settings = SettingsStore.shared
        let samePinnedHost = host.caseInsensitiveCompare(settings.protectHost.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
        let pin = (samePinnedHost && !trustNewCertificate) ? settings.protectCertificateFingerprint : nil
        let client = ProtectClient(host: host, apiKey: apiKey, pinnedFingerprint: pin, onNewFingerprint: { [weak self] fp in
            Task { @MainActor in self?.capturedFingerprint = fp }
        })
        Task {
            defer { client.invalidate() }
            do {
                _ = try await client.metaInfo()
                let cams = try await client.cameras()
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
                        triggers[cam.id] = cam.enabledTriggers.intersection([.ring, .person, .package, .vehicle, .animal])
                    }
                }
                triggerTab = cams.first(where: { selectedCameraIds.contains($0.id) })?.id ?? ""
                step = .cameras
            } catch {
                if case ProtectError.certificateChanged = error { certificateChanged = true }
                keyError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            checking = false
        }
    }

    func finish() {
        let settings = SettingsStore.shared
        // Order matters: setting a different host clears the pinned fingerprint.
        settings.protectHost = host
        if let capturedFingerprint { settings.protectCertificateFingerprint = capturedFingerprint }
        settings.protectAPIKey = apiKey
        for cam in cameras where selectedCameraIds.contains(cam.id) {
            if let index = settings.mappings.firstIndex(where: { $0.protectCameraId == cam.id }) {
                settings.mappings[index].triggers = triggers[cam.id] ?? []
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
            }
            dots
        }
        .padding(.horizontal, 44)
        .padding(.top, 28)
        .padding(.bottom, 22)
        .frame(width: 560, height: 420)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingModel.Step.allCases, id: \.self) { s in
                Circle()
                    .fill(s == model.step ? Color.accentColor : Color.secondary.opacity(0.35))
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
                Button("Neuem Zertifikat vertrauen") { model.checkKey(trustNew: true) }
                    .controlSize(.large)
                    .disabled(model.checking)
            }
            if let consoleURL = URL(string: "https://\(model.host)"), consoleURL.host != nil {
                Link("Konsole im Browser öffnen", destination: consoleURL)
                    .font(.callout)
            }
            Spacer()
            HStack {
                Button("Zurück") { model.step = .console }.controlSize(.large)
                primary(model.checking ? "Prüfe …" : "Verbinden", disabled: model.apiKey.isEmpty || model.checking) { model.checkKey() }
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
            Picker("Kamera", selection: $model.triggerTab) {
                ForEach(selected) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if let cam = current {
                Text("Tippe an, was bei \(cam.name) ein Popup auslöst. Gestrichelt: kann diese Kamera nicht.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                TriggerChips(camera: cam, selection: Binding(
                    get: { model.triggers[cam.id] ?? [] },
                    set: { model.triggers[cam.id] = $0 }
                ))
            }
            Spacer()
            HStack {
                Button("Zurück") { model.step = .cameras }.controlSize(.large)
                primary("Fertig") { model.finish() }
            }
        }
    }
}

/// Toggle chips for trigger kinds; shared with the settings view.
struct TriggerChips: View {
    let camera: ProtectCamera
    @Binding var selection: Set<TriggerKind>

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(TriggerKind.ordered.filter { camera.supportedTriggers.contains($0) || [.ring, .person, .vehicle, .animal, .package].contains($0) }, id: \.self) { kind in
                let supported = camera.supportedTriggers.contains(kind)
                let on = selection.contains(kind)
                Button {
                    if on { selection.remove(kind) } else { selection.insert(kind) }
                } label: {
                    Text(kind.label)
                        .font(.callout.weight(on ? .semibold : .regular))
                        .strikethrough(!supported)
                        .padding(.horizontal, 13).padding(.vertical, 6)
                        .foregroundStyle(on ? Color.white : (supported ? Color.primary : Color.secondary))
                        .background(Capsule().fill(on ? Color.accentColor : Color.clear))
                        .overlay(Capsule().strokeBorder(Color.secondary.opacity(on ? 0 : 0.5),
                                                        style: StrokeStyle(lineWidth: 1, dash: supported ? [] : [3])))
                }
                .buttonStyle(.plain)
                .disabled(!supported)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Minimal wrapping layout (macOS 13+).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX + (bounds.width - row.width) / 2
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
