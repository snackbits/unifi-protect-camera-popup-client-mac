import AppCore
import AppKit
import SwiftUI

/// Callbacks the panel needs from `AppDelegate`.
struct StatusPanelActions {
    let openSettings: () -> Void
    let openHelp: () -> Void
    let quit: () -> Void
    let openCamera: (UUID) -> Void
    let close: () -> Void
    let resize: (CGSize) -> Void
}

/// "Now" for the panel: refreshed on every show and every 15 s while shown.
@MainActor
final class StatusPanelClock: ObservableObject {
    @Published var now = Date()
}

private struct PanelSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// Menu bar panel (docs/design/menue.md): 310 + 2 × 14 wide, radius 14, padding 14, gap 10.
struct StatusPanelView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var events: EventLog
    @ObservedObject var protectEvents: ProtectEventService
    @ObservedObject var relay: WebSocketClient
    @ObservedObject var protect: ProtectSession
    @ObservedObject var clock: StatusPanelClock
    let actions: StatusPanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            let recent = events.history.latest(3)
            if !recent.isEmpty {
                eventList(recent)
            }
            if hasMutes {
                mutedSection
            }
            muteButtons
            CardDivider(color: Tokens.mainBorder)
            footerRow("Einstellungen …", shortcut: "⌘,", action: actions.openSettings)
                .keyboardShortcut(",", modifiers: .command)
            footerRow("Hilfe", shortcut: nil, action: actions.openHelp)
            footerRow("Beenden", shortcut: "⌘Q", action: actions.quit)
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(14)
        .frame(width: 338, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Tokens.win.color))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tokens.mainBorder.color, lineWidth: 1))
        .foregroundStyle(Tokens.fg.color)
        .font(.system(size: 13))
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: PanelSizeKey.self, value: proxy.size)
        })
        .onPreferenceChange(PanelSizeKey.self) { size in actions.resize(size) }
    }

    // MARK: Kopf

    private var header: some View {
        let chip = statusChip
        return HStack {
            Text("Camera Popup").font(.system(size: 14, weight: .bold))
            Spacer()
            Text(chip.text)
                .font(.system(size: 11, weight: .semibold))
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .foregroundStyle(chip.foreground.color)
                .background(Capsule().fill(chip.background.color))
        }
    }

    private var statusChip: (text: String, foreground: ThemeColor, background: ThemeColor) {
        let status: ConnectionStatus
        if protect.client != nil {
            status = protectEvents.status
        } else if settings.mappings.contains(where: \.webhookTriggerEnabled) {
            status = relay.status
        } else {
            return ("Nicht eingerichtet", Tokens.muted, Tokens.btn2)
        }
        switch status {
        case .connected: return ("Zu Hause", Tokens.ok, Tokens.okBg)
        case .connecting: return ("Verbinde …", Tokens.accText, Tokens.accSoft)
        case .disconnected, .outdated: return ("Getrennt", Tokens.muted, Tokens.btn2)
        }
    }

    // MARK: Ereignisse

    private func eventList(_ records: [EventRecord]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(records) { record in
                Button {
                    if let id = UUID(uuidString: record.entryId) { actions.openCamera(id) }
                } label: {
                    HStack(spacing: 10) {
                        thumbnail(record)
                            .frame(width: 54, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(record.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Text(record.cameraName)
                                .font(.system(size: 11))
                                .foregroundStyle(Tokens.muted.color)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text(DisplayText.shortTime(record.date, now: clock.now))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Tokens.muted.color)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ record: EventRecord) -> some View {
        if let image = events.thumbnails[record.id] {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            StripePlaceholder(band: 8)
        }
    }

    // MARK: Stummschalten

    private var globalEnd: Date? {
        settings.muteSchedule.globalEnd(at: clock.now)
    }

    private var cameraMutes: [MuteSchedule.CameraMute] {
        settings.muteSchedule.activeCameraMutes(at: clock.now)
    }

    private var hasMutes: Bool {
        globalEnd != nil || !cameraMutes.isEmpty
    }

    private var mutedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Stummgeschaltet")
            if let end = globalEnd {
                muteRow("Alle Kameras", until: end) { settings.clearGlobalMute() }
            }
            ForEach(cameraMutes, id: \.entry) { mute in
                if let id = UUID(uuidString: mute.entry), let mapping = settings.mapping(forEntry: id) {
                    muteRow(CamerasTab.displayName(mapping), until: mute.until) { settings.clearMute(entryId: id) }
                }
            }
        }
    }

    private func muteRow(_ title: String, until: Date, clear: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            TemplateIcon.speakerMute.image(size: 13).foregroundStyle(Tokens.accText.color)
            Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Text(DisplayText.until(until, now: clock.now))
                .font(.system(size: 11))
                .foregroundStyle(Tokens.muted.color)
            Spacer(minLength: 0)
            Button("Aufheben", action: clear).buttonStyle(LinkButtonStyle())
        }
    }

    private var muteButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Alle Kameras stummschalten")
            HStack(spacing: 6) {
                // Indexed: two equal durations must not collide as identifiers.
                ForEach(Array(settings.muteOptions.enumerated()), id: \.offset) { _, duration in
                    Button {
                        settings.muteAll(for: duration)
                        actions.close()
                    } label: {
                        HStack(spacing: 5) {
                            TemplateIcon.speakerMute.image(size: 13)
                            Text(duration.shortLabel)
                        }
                    }
                    .buttonStyle(SoftButtonStyle())
                }
            }
        }
    }

    // MARK: Fuß

    private func footerRow(_ title: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut).foregroundStyle(Tokens.muted.color)
                }
            }
            .font(.system(size: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Borderless panel under the status item. Closes on outside clicks and when it loses key.
@MainActor
final class StatusPanelController: NSObject, NSWindowDelegate {
    private let makeContent: (StatusPanelClock) -> AnyView
    private let clock = StatusPanelClock()
    private var panel: NSPanel?
    private weak var anchor: NSStatusBarButton?
    private var outsideClickMonitor: Any?
    private var clockTimer: Timer?
    private var lastClose = Date.distantPast

    init(makeContent: @escaping (StatusPanelClock) -> AnyView) {
        self.makeContent = makeContent
    }

    var isShown: Bool {
        panel?.isVisible == true
    }

    func toggle(from button: NSStatusBarButton) {
        if isShown {
            close()
            return
        }
        // Clicking the status item while open first resigns key (closing it); do not reopen.
        guard Date().timeIntervalSince(lastClose) > 0.3 else { return }
        show(from: button)
    }

    func show(from button: NSStatusBarButton) {
        anchor = button
        clock.now = Date()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let content = panel.contentView {
            resize(to: content.fittingSize)
        }
        panel.makeKeyAndOrderFront(nil)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.clock.now = Date() }
        }
    }

    func close() {
        guard isShown else { return }
        panel?.orderOut(nil)
        lastClose = Date()
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        clockTimer?.invalidate()
        clockTimer = nil
    }

    /// Top edge 8 pt under the menu bar, right edge flush with the status item, kept on screen.
    func resize(to size: CGSize) {
        guard let panel, size.width > 0, size.height > 0,
              let button = anchor, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var x = buttonFrame.maxX - size.width
        if let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame {
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        }
        let y = buttonFrame.minY - 8 - size.height
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 338, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: makeContent(clock))
        return panel
    }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
