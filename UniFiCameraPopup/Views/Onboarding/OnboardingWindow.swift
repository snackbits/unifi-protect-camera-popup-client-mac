import AppKit
import SwiftUI

@MainActor
enum OnboardingWindow {
    private static var window: NSWindow?

    /// `.console` / `.key` start an existing setup at that step ("Ändern …", "Ersetzen …");
    /// `.cameras` reuses host and key and continues at step 4 ("Kamera hinzufügen").
    static func show(startAt step: OnboardingModel.Step = .welcome) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let model = OnboardingModel()
        let settings = SettingsStore.shared
        switch step {
        case .welcome:
            break
        case .console:
            model.selectedHost = settings.protectHost
            model.step = .console
            model.scan()
        case .key:
            model.selectedHost = settings.protectHost
            model.step = .key
        case .cameras, .triggers, .travel:
            model.selectedHost = settings.protectHost
            model.apiKey = settings.protectAPIKey
            model.step = .key
            model.checkKey()
        }

        let host = NSHostingController(rootView: OnboardingView(model: model))
        let w = NSWindow(contentViewController: host)
        w.title = "Camera Popup einrichten"
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.setContentSize(NSSize(width: 560, height: 420))
        w.center()
        model.onFinish = { w.close() }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            Task { @MainActor in window = nil }
        }
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
