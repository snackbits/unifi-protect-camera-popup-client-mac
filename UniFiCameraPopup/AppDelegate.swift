import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private let settings = SettingsStore.shared
    private let webSocketClient = WebSocketClient()
    private var statusMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupWebSocket()
        webSocketClient.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        webSocketClient.stop()
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
            button.image = makeStatusBarIcon(tintedWith: statusColor(for: .disconnected))
            button.image?.accessibilityDescription = "UniFi Camera Popup"
        }

        let menu = NSMenu()

        statusMenuItem = NSMenuItem(title: "Status: …", action: nil, keyEquivalent: "")
        statusMenuItem?.isEnabled = false
        menu.addItem(statusMenuItem!)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Einstellungen…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let testItem = NSMenuItem(title: "Test-Popup", action: #selector(showTestPopup), keyEquivalent: "t")
        testItem.target = self
        menu.addItem(testItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Beenden", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu

        Task {
            await observeConnectionStatus()
        }
    }

    private func observeConnectionStatus() async {
        for await status in webSocketClient.$status.values {
            updateStatusMenu(status)
        }
    }

    private func updateStatusMenu(_ status: ConnectionStatus) {
        statusMenuItem?.title = "Status: \(status.menuLabel)"
        if let button = statusItem?.button {
            button.image = makeStatusBarIcon(tintedWith: statusColor(for: status))
        }
    }

    private func statusColor(for status: ConnectionStatus) -> NSColor {
        switch status {
        case .connected: .systemGreen
        case .connecting: .systemYellow
        case .disconnected: .systemRed
        case .outdated: .systemRed
        }
    }

    private func makeStatusBarIcon(tintedWith color: NSColor) -> NSImage? {
        guard let base = NSImage(named: "MenuBarIcon") else { return nil }
        let pointSize: CGFloat = 18
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { bounds in
            color.setFill()
            bounds.fill()
            base.draw(in: bounds, from: NSRect(origin: .zero, size: base.size), operation: .destinationIn, fraction: 1.0)
            return true
        }
        image.isTemplate = false
        return image
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

    @objc private func showTestPopup() {
        PopupController.shared.showTestPopup()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
