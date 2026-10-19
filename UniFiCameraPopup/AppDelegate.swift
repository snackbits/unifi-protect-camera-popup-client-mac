import AppCore
import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var helpWindow: NSWindow?
    private var whatsNewWindow: NSWindow?
    private let settings = SettingsStore.shared
    private let webSocketClient = WebSocketClient()
    private let protectEvents = ProtectEventService()
    /// The relay WebSocket only runs while at least one entry uses webhook triggers.
    private var isRelayRunning = false
    private let updateService = UpdateService()
    private var statusMenuItem: NSMenuItem?
    private var versionMenuItem: NSMenuItem?
    private var updateMenuItem: NSMenuItem?
    private var unmuteMenuItem: NSMenuItem?
    private var camerasMenuItem: NSMenuItem?
    /// The former status menu; shown on right-click / ⌃-click.
    private var classicMenu: NSMenu?
    private lazy var statusPanel: StatusPanelController = StatusPanelController { [unowned self] clock in
        AnyView(StatusPanelView(
            settings: settings,
            events: EventLog.shared,
            protectEvents: protectEvents,
            relay: webSocketClient,
            protect: ProtectSession.shared,
            clock: clock,
            updates: updateService,
            actions: StatusPanelActions(
                openSettings: { [weak self] in
                    self?.statusPanel.close()
                    self?.openSettings()
                },
                openHelp: { [weak self] in
                    self?.statusPanel.close()
                    self?.openHelp()
                },
                quit: { NSApp.terminate(nil) },
                openCamera: { [weak self] id in
                    self?.statusPanel.close()
                    self?.openCamera(entryId: id)
                },
                installUpdate: { [weak self] in
                    self?.statusPanel.close()
                    self?.installUpdate()
                },
                close: { [weak self] in self?.statusPanel.close() },
                resize: { [weak self] size in self?.statusPanel.resize(to: size) }
            )
        ))
    }
    private var updateCheckTimer: Timer?
    private var muteExpiryTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var clockObserver: NSObjectProtocol?
    private var dndCheckTimer: Timer?
    private var focusMonitor: FocusMonitor?
    private var connectionStatus: ConnectionStatus = .disconnected
    private var protectStatus: ConnectionStatus = .disconnected
    /// Mirrors `ProtectSession.shared.client != nil`; webhook-only setups show no Protect status.
    private var isProtectConfigured = false
    /// Mirrors `ConnectionRouter.shared.route == .tunnel` for the status line.
    private var isViaTunnel = false
    /// Prevents retry loops when an automatic install fails.
    /// Version the update question was shown for in this run („Später“ asks again after a restart).
    private var updatePromptedVersionId: String?

    /// How often to poll the server for a newer build while the app is running.
    private let updateCheckInterval: TimeInterval = 6 * 60 * 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        SnapshotRenderer.runIfRequested()
        #endif
        settings.pruneMutes()
        AppActions.openHelp = { [weak self] in self?.openHelp() }
        settings.reconcileLaunchAtLogin()
        setupStatusItem()
        if !settings.isProtectConfigured && settings.mappings.isEmpty {
            OnboardingWindow.show()
        }
        setupWebSocket()
        setupHotkeys()
        syncRelayConnection(mappings: settings.mappings)
        startUpdateChecks()
        showWhatsNewIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        webSocketClient.stop()
        protectEvents.stop()
        GlobalHotkeyManager.shared.stop()
        updateCheckTimer?.invalidate()
        muteExpiryTimer?.invalidate()
        dndCheckTimer?.invalidate()
        focusMonitor?.stop()
        PopupController.shared.dismiss()
    }

    private func setupWebSocket() {
        webSocketClient.onTrigger = { event in
            PopupController.shared.show(event: event)
        }
        protectEvents.onTrigger = { event in
            PopupController.shared.show(event: event)
        }
        // Route first: it decides whether ProtectSession talks to the console directly or via the tunnel.
        ConnectionRouter.shared.start()
        ProtectSession.shared.reconnect()
        protectEvents.start()
    }

    /// Starts or stops the relay WebSocket when entries gain or lose webhook triggers.
    private func syncRelayConnection(mappings: [WebhookMapping]) {
        let needed = mappings.contains(where: \.webhookTriggerEnabled)
        if needed, !isRelayRunning {
            isRelayRunning = true
            webSocketClient.start()
        } else if !needed, isRelayRunning {
            isRelayRunning = false
            webSocketClient.stop()
        }
        updateStatusMenu()
    }

    private func setupHotkeys() {
        GlobalHotkeyManager.shared.start { [weak self] entryId in
            self?.openHotkeyPopup(for: entryId)
        }
        GlobalHotkeyManager.shared.sync(mappings: settings.mappings)

        Task {
            await observeHotkeyMappings()
        }
    }

    private func openHotkeyPopup(for entryId: UUID) {
        guard let mapping = settings.mappings.first(where: { $0.entryId == entryId }) else { return }
        PopupController.shared.showHotkeyPopup(for: mapping)
    }

    private func observeHotkeyMappings() async {
        for await mappings in settings.$mappings.values {
            GlobalHotkeyManager.shared.sync(mappings: mappings)
            syncRelayConnection(mappings: mappings)
            EventLog.shared.removeEntries(notIn: Set(mappings.map(\.entryId)))
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = makeStatusBarIcon(
                tintedWith: statusColor(for: .disconnected),
                showSuppressedBadge: showPopupSuppressedBadge
            )
            button.image?.accessibilityDescription = "UniFi Camera Popup"
        }

        let menu = NSMenu()
        menu.delegate = self

        statusMenuItem = NSMenuItem(title: "Status: …", action: nil, keyEquivalent: "")
        statusMenuItem?.isEnabled = false
        menu.addItem(statusMenuItem!)

        let versionMenuItem = NSMenuItem(
            title: currentVersionLabel,
            action: nil,
            keyEquivalent: ""
        )
        versionMenuItem.isEnabled = false
        menu.addItem(versionMenuItem)
        self.versionMenuItem = versionMenuItem

        let updateMenuItem = NSMenuItem(
            title: "Auf neue Version aktualisieren",
            action: #selector(installUpdate),
            keyEquivalent: ""
        )
        updateMenuItem.target = self
        updateMenuItem.isHidden = true
        menu.addItem(updateMenuItem)
        self.updateMenuItem = updateMenuItem

        menu.addItem(NSMenuItem.separator())

        let unmuteMenuItem = NSMenuItem(
            title: "Stummschaltung aufheben",
            action: #selector(clearMute),
            keyEquivalent: ""
        )
        unmuteMenuItem.target = self
        unmuteMenuItem.isHidden = true
        if let unmuteImage = NSImage(systemSymbolName: "bell.slash.fill", accessibilityDescription: "Stummschaltung aufheben") {
            unmuteImage.isTemplate = true
            unmuteMenuItem.image = unmuteImage
        }
        menu.addItem(unmuteMenuItem)
        self.unmuteMenuItem = unmuteMenuItem

        let camerasMenuItem = NSMenuItem(title: "Kameras", action: nil, keyEquivalent: "")
        camerasMenuItem.submenu = NSMenu()
        camerasMenuItem.isHidden = true
        menu.addItem(camerasMenuItem)
        self.camerasMenuItem = camerasMenuItem

        let setupItem = NSMenuItem(title: "Einrichtung …", action: #selector(openOnboarding), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)

        let settingsItem = NSMenuItem(title: "Einstellungen…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let helpItem = NSMenuItem(title: "Hilfe", action: #selector(openHelp), keyEquivalent: "")
        helpItem.target = self
        if let helpImage = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "Hilfe") {
            helpImage.isTemplate = true
            helpItem.image = helpImage
        }
        menu.addItem(helpItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Beenden", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        classicMenu = menu
        if let button = statusItem?.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        Task {
            await observeConnectionStatus()
        }
        Task {
            await observeProtectStatus()
        }
        Task {
            await observeProtectClient()
        }
        Task {
            await observeRoute()
        }
        Task {
            await observeUpdateState()
        }
        Task {
            await observePopupSuppressionState()
        }
        startDNDPolling()
        scheduleMuteExpiryRefresh()
        observeClockJumps()
    }

    /// Timers do not fire reliably across sleep or a clock change: re-prune and re-arm.
    private func observeClockJumps() {
        let refresh: (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.settings.pruneMutes()
                self?.scheduleMuteExpiryRefresh()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: refresh)
        clockObserver = NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main, using: refresh)
    }

    private func observeConnectionStatus() async {
        for await status in webSocketClient.$status.values {
            connectionStatus = status
            updateStatusMenu()
            // The server dropped us for being outdated → a newer build exists.
            if status == .outdated {
                Task { await updateService.checkForUpdates() }
            }
        }
    }

    private func observeUpdateState() async {
        for await state in updateService.$state.values {
            updateUpdateMenu(state)
        }
    }

    private func observeProtectStatus() async {
        for await status in protectEvents.$status.values {
            protectStatus = status
            // Tunnel liveness is judged only while the events socket (pings every 30 s) is open.
            TunnelController.shared.eventsSocketChanged(open: status == .connected)
            updateStatusMenu()
        }
    }

    private func observeRoute() async {
        // `@Published` emits in `willSet`: use the emitted value, not the property.
        for await route in ConnectionRouter.shared.$route.values {
            isViaTunnel = route == .tunnel
            updateStatusMenu()
        }
    }

    private func observeProtectClient() async {
        // `@Published` emits in `willSet`: use the emitted value, not the property.
        for await client in ProtectSession.shared.$client.values {
            isProtectConfigured = client != nil
            updateStatusMenu()
        }
    }

    private func updateStatusMenu() {
        var parts: [String] = []
        if isProtectConfigured {
            parts.append(protectStatusLabel)
        }
        if isRelayRunning {
            parts.append("Status: \(connectionStatus.menuLabel)")
        }
        statusMenuItem?.title = parts.isEmpty ? "Nicht eingerichtet" : parts.joined(separator: " · ")
        updateStatusBarIcon()
    }

    private var protectStatusLabel: String {
        let base = switch protectStatus {
        case .connected: "Protect: verbunden"
        case .connecting: "Protect: verbinde …"
        case .disconnected, .outdated: "Protect: getrennt"
        }
        return isViaTunnel ? "\(base) · unterwegs" : base
    }

    /// The icon shows the worst of the connections in use (Protect once configured,
    /// the relay while webhook triggers exist).
    private var iconStatus: ConnectionStatus {
        var statuses: [ConnectionStatus] = []
        if ProtectSession.shared.client != nil { statuses.append(protectStatus) }
        if isRelayRunning { statuses.append(connectionStatus) }
        if let failed = statuses.first(where: { $0 == .disconnected || $0 == .outdated }) { return failed }
        if statuses.contains(.connecting) { return .connecting }
        return statuses.isEmpty ? .disconnected : .connected
    }

    private var showPopupSuppressedBadge: Bool {
        if settings.isMuted { return true }
        if settings.disableDuringDND, DoNotDisturbChecker.isActive { return true }
        return false
    }

    private func updateStatusBarIcon() {
        statusItem?.button?.image = makeStatusBarIcon(
            tintedWith: statusColor(for: iconStatus),
            showSuppressedBadge: showPopupSuppressedBadge
        )
    }

    private func observePopupSuppressionState() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                for await schedule in self.settings.$muteSchedule.values {
                    self.scheduleMuteExpiryRefresh(schedule)
                }
            }
            group.addTask { @MainActor in
                for await _ in self.settings.$disableDuringDND.values {
                    self.updateStatusBarIcon()
                }
            }
            group.addTask { @MainActor in
                for await mode in self.settings.$appearance.values {
                    NSApp.appearance = mode.appearanceName.flatMap { NSAppearance(named: $0) }
                }
            }
        }
    }

    /// Refreshes the icon now and again when the next mute ends; then prunes ended mutes.
    private func scheduleMuteExpiryRefresh(_ schedule: MuteSchedule? = nil) {
        muteExpiryTimer?.invalidate()
        muteExpiryTimer = nil
        updateStatusBarIcon()

        guard let next = (schedule ?? settings.muteSchedule).nextExpiry(after: Date()) else { return }
        let timer = Timer(timeInterval: max(next.timeIntervalSinceNow, 0.5), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.settings.pruneMutes()
                self?.scheduleMuteExpiryRefresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        muteExpiryTimer = timer
    }

    private func startDNDPolling() {
        // Instant, event-driven updates when the Focus database changes.
        focusMonitor = FocusMonitor { [weak self] in
            self?.updateStatusBarIcon()
        }
        focusMonitor?.start()

        // Low-frequency safety net: catches scheduled Focus windows turning on/off
        // and works even if the file watch couldn't arm (e.g. no Full Disk Access).
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusBarIcon()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dndCheckTimer = timer
    }

    private func updateUpdateMenu(_ state: UpdateState) {
        guard let versionMenuItem, let updateMenuItem else { return }

        switch state {
        case .idle, .checking, .upToDate:
            versionMenuItem.title = currentVersionLabel
            updateMenuItem.isHidden = true
            updateMenuItem.isEnabled = true

        case .available(let buildNumber, let shortVersion):
            let target = shortVersion.map { "\($0) (\(buildNumber))" } ?? "\(buildNumber)"
            versionMenuItem.title = "\(currentVersionLabel) → \(target)"
            updateMenuItem.title = "Auf neue Version aktualisieren"
            updateMenuItem.isHidden = false
            updateMenuItem.isEnabled = true
            promptForUpdateIfNeeded()

        case .downloading:
            updateMenuItem.title = "Lade neue Version…"
            updateMenuItem.isHidden = false
            updateMenuItem.isEnabled = false

        case .installing:
            updateMenuItem.title = "Installiere…"
            updateMenuItem.isHidden = false
            updateMenuItem.isEnabled = false

        case .failed(let message):
            updateMenuItem.title = "Auf neue Version aktualisieren"
            updateMenuItem.isHidden = updateService.availableManifest == nil
            updateMenuItem.isEnabled = true
            presentUpdateError(message)
        }
    }

    private func presentUpdateError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Update fehlgeschlagen"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        updateService.dismissError()
    }

    private func startUpdateChecks() {
        Task { await updateService.checkForUpdates() }

        let timer = Timer(timeInterval: updateCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateService.checkForUpdates()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        updateCheckTimer = timer
    }

    private func statusColor(for status: ConnectionStatus) -> NSColor {
        switch status {
        case .connected: .systemGreen
        case .connecting: .systemYellow
        case .disconnected: .systemRed
        case .outdated: .systemRed
        }
    }

    private func makeStatusBarIcon(tintedWith color: NSColor, showSuppressedBadge: Bool) -> NSImage? {
        guard let base = NSImage(named: "MenuBarIcon") else { return nil }
        let pointSize: CGFloat = 18
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { bounds in
            color.setFill()
            bounds.fill()
            base.draw(in: bounds, from: NSRect(origin: .zero, size: base.size), operation: .destinationIn, fraction: 1.0)

            if showSuppressedBadge, let zzz = NSImage(named: "ZzzBadge") {
                let badgeSize = pointSize * 0.58
                let badgeRect = NSRect(
                    x: bounds.maxX - badgeSize + 2,
                    y: bounds.minY - 1,
                    width: badgeSize,
                    height: badgeSize
                )
                NSColor.systemOrange.setFill()
                badgeRect.fill()
                zzz.draw(
                    in: badgeRect,
                    from: NSRect(origin: .zero, size: zzz.size),
                    operation: .destinationIn,
                    fraction: 1.0
                )
            }

            return true
        }
        image.isTemplate = false
        return image
    }

    /// A new version asks once per run instead of installing silently: the keychain password
    /// prompt after the restart only makes sense when the user chose to update.
    private func promptForUpdateIfNeeded() {
        guard settings.autoUpdate,
              let manifest = updateService.availableManifest,
              !updateService.isInstalling,
              manifest.versionId != updatePromptedVersionId else {
            return
        }
        updatePromptedVersionId = manifest.versionId
        // Not on top of a popup or another dialog that is being dealt with right now.
        DispatchQueue.main.async { [weak self] in self?.confirmAndInstall(manifest) }
    }

    @objc private func installUpdate() {
        guard let manifest = updateService.availableManifest else { return }
        updatePromptedVersionId = manifest.versionId
        confirmAndInstall(manifest)
    }

    private func confirmAndInstall(_ manifest: UpdateManifest) {
        guard !updateService.isInstalling, NSApp.modalWindow == nil else { return }
        let alert = NSAlert()
        let version = manifest.shortVersion.map { "Version \($0)" } ?? "Eine neue Version"
        alert.messageText = "\(version) ist verfügbar"
        var info = ""
        if let notes = manifest.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            info += "\(notes)\n\n"
        }
        info += "Die App lädt das Update, installiert es und startet neu. Danach fragt macOS eventuell "
            + "einmal nach deinem Anmeldepasswort, damit die neue Version deine gespeicherten Zugangsdaten "
            + "(API-Schlüssel, Tunnel) lesen darf – dann „Immer erlauben“ (Always Allow) wählen."
        alert.informativeText = info
        alert.addButton(withTitle: "Jetzt aktualisieren")
        alert.addButton(withTitle: "Später")
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await updateService.installUpdate() }
    }

    @objc private func openOnboarding() { OnboardingWindow.show() }

    /// Left click: template panel. Right click or ⌃-click: the former menu (version, update, cameras …).
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsClassicMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsClassicMenu {
            statusPanel.close()
            statusItem?.menu = classicMenu
            sender.performClick(nil)
            statusItem?.menu = nil
        } else {
            // Like the former menu: every opening looks for a newer build in the background.
            if !statusPanel.isShown { Task { await updateService.checkForUpdates() } }
            statusPanel.toggle(from: sender)
        }
    }

    private func openCamera(entryId: UUID) {
        guard let mapping = settings.mappings.first(where: { $0.entryId == entryId }) else { return }
        PopupController.shared.showHotkeyPopup(for: mapping)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show(webSocketClient: webSocketClient, protectEvents: protectEvents)
    }

    private var currentVersionLabel: String {
        "Version: \(AppConfig.shortVersion) (\(AppConfig.buildNumber))"
    }

    /// Announces what changed once after an update. Fresh installs see nothing.
    private func showWhatsNewIfNeeded() {
        let info = WhatsNewService.pendingUpdateInfo()
        // Mark right away so the popup never reappears, however it is closed.
        WhatsNewService.markCurrentVersionSeen()
        guard let info else { return }

        let view = WhatsNewView(info: info) { [weak self] in
            self?.whatsNewWindow?.close()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Was ist neu – UniFi Camera Popup"
        window.center()
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        whatsNewWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openHelp() {
        if helpWindow == nil {
            let view = HelpView()

            helpWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            helpWindow?.title = "Hilfe – UniFi Camera Popup"
            helpWindow?.center()
            helpWindow?.contentView = NSHostingView(rootView: view)
            helpWindow?.isReleasedWhenClosed = false
        }

        helpWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func clearMute() {
        settings.clearMute()
        updateStatusBarIcon()
        scheduleMuteExpiryRefresh()
    }

    @objc private func openCameraFromMenu(_ sender: NSMenuItem) {
        guard let entryIdString = sender.representedObject as? String,
              let entryId = UUID(uuidString: entryIdString),
              let mapping = settings.mappings.first(where: { $0.entryId == entryId }) else {
            return
        }
        PopupController.shared.showHotkeyPopup(for: mapping)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        // Refresh the update status whenever the user opens the menu.
        Task { await updateService.checkForUpdates() }
        updateMuteMenuItem()
        updateCamerasMenu()
    }

    private func updateCamerasMenu() {
        guard let camerasMenuItem, let submenu = camerasMenuItem.submenu else { return }

        submenu.removeAllItems()
        let mappings = settings.mappings
        camerasMenuItem.isHidden = mappings.isEmpty

        for mapping in mappings {
            let item = NSMenuItem(
                title: cameraMenuTitle(for: mapping),
                action: #selector(openCameraFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mapping.entryId.uuidString
            item.isEnabled = canOpenCameraPopup(mapping)
            submenu.addItem(item)
        }
    }

    private func cameraMenuTitle(for mapping: WebhookMapping) -> String {
        let label = mapping.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { return label }

        let slug = mapping.webhookId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !slug.isEmpty { return slug }

        return "Kamera"
    }

    private func canOpenCameraPopup(_ mapping: WebhookMapping) -> Bool {
        mapping.hasStreamSource
    }

    private func updateMuteMenuItem() {
        guard let unmuteMenuItem else { return }

        let now = Date()
        let schedule = settings.muteSchedule
        let cameraCount = schedule.activeCameraMutes(at: now).count
        if let globalEnd = schedule.globalEnd(at: now) {
            let minutes = max(1, Int((globalEnd.timeIntervalSince(now) / 60).rounded(.up)))
            unmuteMenuItem.title = "Stummschaltung aufheben (noch \(minutes) Min.)"
        } else if cameraCount > 0 {
            unmuteMenuItem.title = cameraCount == 1
                ? "Stummschaltung aufheben (1 Kamera)"
                : "Stummschaltung aufheben (\(cameraCount) Kameras)"
        } else {
            unmuteMenuItem.isHidden = true
            return
        }
        unmuteMenuItem.isHidden = false
    }
}
