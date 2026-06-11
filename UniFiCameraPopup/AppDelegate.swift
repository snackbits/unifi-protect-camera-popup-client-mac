import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var helpWindow: NSWindow?
    private let settings = SettingsStore.shared
    private let webSocketClient = WebSocketClient()
    private let updateService = UpdateService()
    private var statusMenuItem: NSMenuItem?
    private var versionMenuItem: NSMenuItem?
    private var updateMenuItem: NSMenuItem?
    private var unmuteMenuItem: NSMenuItem?
    private var updateCheckTimer: Timer?
    private var muteExpiryTimer: Timer?
    private var dndCheckTimer: Timer?
    private var focusMonitor: FocusMonitor?
    private var connectionStatus: ConnectionStatus = .disconnected
    /// Prevents retry loops when an automatic install fails.
    private var autoInstallAttemptedVersionId: String?

    /// How often to poll the server for a newer build while the app is running.
    private let updateCheckInterval: TimeInterval = 6 * 60 * 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupWebSocket()
        webSocketClient.start()
        startUpdateChecks()
    }

    func applicationWillTerminate(_ notification: Notification) {
        webSocketClient.stop()
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
            title: "Version: \(AppConfig.buildNumber)",
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

        statusItem?.menu = menu

        Task {
            await observeConnectionStatus()
        }
        Task {
            await observeUpdateState()
        }
        Task {
            await observePopupSuppressionState()
        }
        startDNDPolling()
        scheduleMuteExpiryRefresh()
    }

    private func observeConnectionStatus() async {
        for await status in webSocketClient.$status.values {
            updateStatusMenu(status)
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

    private func updateStatusMenu(_ status: ConnectionStatus) {
        connectionStatus = status
        statusMenuItem?.title = "Status: \(status.menuLabel)"
        updateStatusBarIcon()
    }

    private var showPopupSuppressedBadge: Bool {
        if settings.isMuted { return true }
        if settings.disableDuringDND, DoNotDisturbChecker.isActive { return true }
        return false
    }

    private func updateStatusBarIcon() {
        statusItem?.button?.image = makeStatusBarIcon(
            tintedWith: statusColor(for: connectionStatus),
            showSuppressedBadge: showPopupSuppressedBadge
        )
    }

    private func observePopupSuppressionState() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                for await _ in self.settings.$muteUntil.values {
                    self.updateStatusBarIcon()
                    self.scheduleMuteExpiryRefresh()
                }
            }
            group.addTask { @MainActor in
                for await _ in self.settings.$disableDuringDND.values {
                    self.updateStatusBarIcon()
                }
            }
        }
    }

    private func scheduleMuteExpiryRefresh() {
        muteExpiryTimer?.invalidate()
        muteExpiryTimer = nil

        guard settings.isMuted, let muteUntil = settings.muteUntil else {
            updateStatusBarIcon()
            return
        }

        let interval = muteUntil.timeIntervalSinceNow
        guard interval > 0 else {
            updateStatusBarIcon()
            return
        }

        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusBarIcon()
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
            versionMenuItem.title = "Version: \(AppConfig.buildNumber)"
            updateMenuItem.isHidden = true
            updateMenuItem.isEnabled = true

        case .available(let buildNumber, _):
            versionMenuItem.title = "Version: \(AppConfig.buildNumber) → \(buildNumber)"
            updateMenuItem.title = "Auf neue Version aktualisieren"
            updateMenuItem.isHidden = false
            updateMenuItem.isEnabled = true
            autoInstallUpdateIfNeeded()

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

    private func autoInstallUpdateIfNeeded() {
        guard settings.autoUpdate,
              let manifest = updateService.availableManifest,
              !updateService.isInstalling,
              manifest.versionId != autoInstallAttemptedVersionId else {
            return
        }

        autoInstallAttemptedVersionId = manifest.versionId
        Task { await updateService.installUpdate() }
    }

    @objc private func installUpdate() {
        guard let manifest = updateService.availableManifest else { return }

        let alert = NSAlert()
        alert.messageText = "Neue Version installieren?"
        var info = "Version \(manifest.buildNumber) wird heruntergeladen und installiert. "
            + "Die App startet anschließend neu."
        if let notes = manifest.notes, !notes.isEmpty {
            info += "\n\n\(notes)"
        }
        alert.informativeText = info
        alert.addButton(withTitle: "Aktualisieren")
        alert.addButton(withTitle: "Abbrechen")
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await updateService.installUpdate() }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView()
                .environmentObject(settings)
                .environmentObject(webSocketClient)

            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.title = "UniFi Camera Popup"
            settingsWindow?.center()
            settingsWindow?.contentView = NSHostingView(rootView: view)
            settingsWindow?.isReleasedWhenClosed = false
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
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

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        // Refresh the update status whenever the user opens the menu.
        Task { await updateService.checkForUpdates() }
        updateMuteMenuItem()
    }

    private func updateMuteMenuItem() {
        guard let unmuteMenuItem else { return }

        guard settings.isMuted, let muteUntil = settings.muteUntil else {
            unmuteMenuItem.isHidden = true
            return
        }

        let remaining = max(0, Int(muteUntil.timeIntervalSinceNow.rounded(.up)))
        let minutes = (remaining + 59) / 60
        unmuteMenuItem.title = minutes > 0
            ? "Stummschaltung aufheben (noch \(minutes) Min.)"
            : "Stummschaltung aufheben"
        unmuteMenuItem.isHidden = false
    }
}
