import AppCore
import AppKit
import ProtectKit
import SwiftUI

/// Einstellungen › Kameras (docs/design/einstellungen-kameras.md).
struct CamerasTab: View {
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject private var protect = ProtectSession.shared
    @StateObject private var addAnchor = ViewAnchor()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Tokens.border.color).frame(width: 1)
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await protect.refreshCameras() }
        .onAppear(perform: ensureSelection)
        .onChange(of: settings.mappings.map(\.entryId)) { _ in ensureSelection() }
    }

    // MARK: Sidebar (190 + 2 × 8 content-box, + 1 border = 207)

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(settings.mappings) { mapping in
                        sidebarItem(mapping)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
            }
            Button("Kamera hinzufügen …", action: addCamera)
                .buttonStyle(LinkButtonStyle())
                .background(AnchorView(anchor: addAnchor))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 206)
        .background(Tokens.side.color)
    }

    private func sidebarItem(_ mapping: WebhookMapping) -> some View {
        let selected = mapping.entryId == navigation.selectedEntry
        return Button { navigation.selectedEntry = mapping.entryId } label: {
            HStack(spacing: 8) {
                CameraThumbnail(cameraId: mapping.protectCameraId)
                    .frame(width: 34, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 0) {
                    Text(Self.displayName(mapping))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(stateText(mapping))
                        .font(.system(size: 10))
                        .opacity(0.85)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .foregroundStyle(selected ? Color.white : Tokens.fg.color)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Tokens.accent.color : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    static func displayName(_ mapping: WebhookMapping) -> String {
        let label = mapping.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { return label }
        let slug = mapping.webhookId.trimmingCharacters(in: .whitespacesAndNewlines)
        return slug.isEmpty ? "Kamera" : slug
    }

    private func stateText(_ mapping: WebhookMapping) -> String {
        let labels = mapping.protectCameraId == nil
            ? []
            : TriggerKind.displayOrder.filter { mapping.triggers.contains($0) }.map(\.label)
        return DisplayText.cameraState(
            triggerLabels: labels,
            webhook: mapping.webhookTriggerEnabled,
            mutedUntil: settings.muteSchedule.cameraMuteEnd(entry: mapping.entryId.uuidString, at: Date())
        )
    }

    private func addCamera() {
        guard let view = addAnchor.view else { return }
        let fromProtect = "Aus Protect wählen …"
        let webhookOnly = "Nur per Webhook"
        let titles = settings.isProtectConfigured ? [fromProtect, webhookOnly] : [webhookOnly]
        MenuPresenter.popUp(titles: titles, selectedIndex: nil, in: view) { index in
            if titles[index] == fromProtect {
                OnboardingWindow.show(startAt: .cameras)
            } else {
                settings.addMapping()
                navigation.selectedEntry = settings.mappings.last?.entryId
            }
        }
    }

    private func ensureSelection() {
        let ids = settings.mappings.map(\.entryId)
        if let selected = navigation.selectedEntry, ids.contains(selected) { return }
        navigation.selectedEntry = ids.first
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let id = navigation.selectedEntry, let binding = binding(for: id) {
            CameraDetail(mapping: binding, onRemoved: ensureSelection)
                .id(id)
        } else {
            VStack(spacing: 10) {
                Text("Noch keine Kamera eingerichtet.").foregroundStyle(Tokens.muted.color)
                Button(settings.isProtectConfigured ? "Kameras aus Protect wählen …" : "Einrichtung starten …") {
                    OnboardingWindow.show(startAt: settings.isProtectConfigured ? .cameras : .welcome)
                }
                .buttonStyle(FieldButtonStyle())
            }
        }
    }

    /// Looks the entry up by id on every access, so removing it never indexes out of range.
    private func binding(for id: UUID) -> Binding<WebhookMapping>? {
        guard let current = settings.mappings.first(where: { $0.entryId == id }) else { return nil }
        return Binding(
            get: { settings.mappings.first { $0.entryId == id } ?? current },
            set: { updated in
                if let index = settings.mappings.firstIndex(where: { $0.entryId == id }) {
                    settings.mappings[index] = updated
                }
            }
        )
    }
}

struct ActionEditorContext: Identifiable {
    let id = UUID()
    let action: CameraAction
    let isNew: Bool
}

struct CameraDetail: View {
    @Binding var mapping: WebhookMapping
    let onRemoved: () -> Void

    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var protect = ProtectSession.shared
    @ObservedObject private var events = EventLog.shared
    #if DEBUG
    @State private var advancedExpanded = SnapshotRenderer.expandCameraAdvanced
    #else
    @State private var advancedExpanded = false
    #endif
    @State private var editor: ActionEditorContext?
    @State private var confirmRemoval = false

    private var camera: ProtectCamera? {
        guard let id = mapping.protectCameraId else { return nil }
        return protect.cameras.first { $0.id == id }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header
                        triggersSection
                        optionsCard
                        buttonsSection
                        Spacer(minLength: 0)
                        // „Kamera entfernen“ stays visible with „Erweitert“ collapsed (Phase 5).
                        HStack {
                            DisclosureButton(title: "Erweitert", expanded: $advancedExpanded)
                            Spacer()
                            Button("Kamera entfernen") { confirmRemoval = true }
                                .buttonStyle(LinkButtonStyle(color: Tokens.danger))
                        }
                        .id("advanced")
                        if advancedExpanded {
                            CameraAdvancedSection(
                                mapping: $mapping,
                                lastTriggered: events.lastTriggered(entryId: mapping.entryId)
                            )
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 22)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .topLeading)
                }
                .onAppear {
                    guard advancedExpanded else { return }
                    DispatchQueue.main.async { proxy.scrollTo("advanced", anchor: .top) }
                }
                .onChange(of: advancedExpanded) { expanded in
                    guard expanded else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("advanced", anchor: .top) }
                    }
                }
            }
        }
        .sheet(item: $editor) { context in
            ActionEditorSheet(
                action: context.action,
                isNew: context.isNew,
                onSave: save,
                onDelete: context.isNew ? nil : { delete(context.action.id) }
            )
        }
        .alert("Kamera entfernen?", isPresented: $confirmRemoval) {
            Button("Abbrechen", role: .cancel) {}
            Button("Entfernen", role: .destructive) {
                settings.removeMapping(id: mapping.entryId)
                onRemoved()
            }
        } message: {
            Text("Möchtest du die Kamera „\(CamerasTab.displayName(mapping))“ wirklich entfernen?")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(CamerasTab.displayName(mapping))
                .font(.system(size: 16, weight: .bold))
                .lineLimit(1)
            Spacer()
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Tokens.muted.color)
                .lineLimit(1)
        }
    }

    private var subtitle: String {
        guard mapping.protectCameraId != nil else { return "nur Webhook" }
        guard let camera else { return "" }
        return [camera.modelName, camera.hasSpeaker ? "Lautsprecher" : nil]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var triggersSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: "Auslöser")
            if let camera {
                TriggerChips(camera: camera, selection: $mapping.triggers, size: .small)
            } else if mapping.protectCameraId != nil {
                Text(protect.lastError ?? "Kamera wird geladen …")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.muted.color)
            } else {
                Text("Diese Kamera meldet sich nur per Webhook (siehe „Erweitert“).")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.muted.color)
            }
        }
    }

    private var optionsCard: some View {
        Card(radius: 9) {
            HotkeyRecorderView(hotkey: $mapping.hotkey, conflictMessage: hotkeyConflictMessage)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            CardDivider()
            CardToggleRow(title: "Hinweiston beim Öffnen", isOn: $mapping.chimeOnOpen, vertical: 8, horizontal: 12)
            CardDivider()
            CardToggleRow(title: "Zoom und Ausschnitt merken", isOn: $mapping.rememberZoom, vertical: 8, horizontal: 12)
            CardDivider()
            CardToggleRow(title: "Ton des Livebilds", isOn: $mapping.soundEnabled, vertical: 8, horizontal: 12)
        }
    }

    private var buttonsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Buttons im Popup (max. \(WebhookMapping.maxActions))")
            Card(radius: 9) {
                ForEach(mapping.actions) { action in
                    ActionRowLayout {
                        Text(action.trimmedTitle.isEmpty ? "Ohne Titel" : action.trimmedTitle)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text(action.method.rawValue)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.vertical, 2)
                            .padding(.horizontal, 5)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(Tokens.accText.color)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Tokens.accSoft.color))
                        Text(DisplayText.actionAddress(action.url))
                            .foregroundStyle(Tokens.muted.color)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Button("Ändern") { editor = ActionEditorContext(action: action, isNew: false) }
                            .buttonStyle(LinkButtonStyle())
                    }
                    .font(.system(size: 12))
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    CardDivider()
                }
                if mapping.actions.count < WebhookMapping.maxActions {
                    Button("Button hinzufügen …") { editor = ActionEditorContext(action: CameraAction(), isNew: true) }
                        .buttonStyle(LinkButtonStyle())
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                } else {
                    Text("Höchstens drei Buttons.")
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.muted.color)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                }
            }
        }
    }

    private func save(_ action: CameraAction) {
        if let index = mapping.actions.firstIndex(where: { $0.id == action.id }) {
            mapping.actions[index] = action
        } else if mapping.actions.count < WebhookMapping.maxActions {
            mapping.actions.append(action)
        }
    }

    private func delete(_ id: UUID) {
        mapping.actions.removeAll { $0.id == id }
    }

    // From the former SettingsView.
    private var hotkeyConflictMessage: String? {
        guard let hotkey = mapping.hotkey else { return nil }

        let duplicates = settings.mappings.filter { $0.hotkey == hotkey }
        if duplicates.count > 1 {
            return conflictNamesMessage(prefix: "Dieses Tastenkürzel ist", mappings: duplicates)
        }
        if hotkey.isSequence, let prefix = hotkey.steps.first {
            let conflicts = settings.mappings.filter {
                guard mapping.entryId != $0.entryId, let other = $0.hotkey else { return false }
                return !other.isSequence && other.steps.first == prefix
            }
            if !conflicts.isEmpty {
                return conflictNamesMessage(prefix: "Die erste Taste kollidiert mit dem Einzel-Shortcut von", mappings: conflicts)
            }
        }
        if !hotkey.isSequence, let prefix = hotkey.steps.first {
            let conflicts = settings.mappings.filter {
                guard mapping.entryId != $0.entryId, let other = $0.hotkey else { return false }
                return other.isSequence && other.steps.first == prefix
            }
            if !conflicts.isEmpty {
                return conflictNamesMessage(prefix: "Dieser Shortcut blockiert die Sequenz von", mappings: conflicts)
            }
        }
        return nil
    }

    private func conflictNamesMessage(prefix: String, mappings: [WebhookMapping]) -> String {
        let names = mappings
            .map { $0.label.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return names.isEmpty ? "\(prefix) mehreren Kameras." : "\(prefix) \(names.joined(separator: ", "))."
    }
}

/// CSS grid `minmax(0,1fr) 46px minmax(0,1.6fr) 44px`, gap 8 (popup button rows).
struct ActionRowLayout: Layout {
    private static let gap: CGFloat = 8

    static func columnWidths(total: CGFloat) -> [CGFloat] {
        let flexible = max(total - 46 - 44 - gap * 3, 0)
        return [flexible / 2.6, 46, flexible * 1.6 / 2.6, 44]
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 480
        let widths = Self.columnWidths(total: width)
        let height = zip(subviews, widths)
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
            .max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, Self.columnWidths(total: bounds.width)) {
            subview.place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: width, height: nil)
            )
            x += width + Self.gap
        }
    }
}

/// Snapshot of a Protect camera, striped placeholder while loading or without picture.
struct CameraThumbnail: View {
    let cameraId: String?
    var band: CGFloat = 6
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            StripePlaceholder(band: band)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .task(id: cameraId) {
            image = nil
            guard let cameraId else { return }
            image = await ProtectSession.shared.snapshot(cameraId: cameraId)
        }
    }
}
