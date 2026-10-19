#if DEBUG
import AppCore
import AppKit
import ProtectKit
import SwiftUI

/// Debug-only: `--render-snapshots <dir>` renders the template screens with sample data to PNG
/// (2×, light and dark) and exits. All settings go to a throwaway `UserDefaults` suite
/// (see `SettingsStore` / `EventLog`), never to the real defaults domain.
enum SnapshotRenderer {
    static let argument = "--render-snapshots"
    static let suiteName = "com.snackbits.UniFiCameraPopup.snapshots"

    /// Flag present and followed by a directory argument.
    static var isActive: Bool { outputDirectory != nil }

    private static var outputDirectory: URL? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: argument), args.indices.contains(index + 1),
              !args[index + 1].hasPrefix("-") else { return nil }
        return URL(fileURLWithPath: args[index + 1], isDirectory: true)
    }

    static let isolatedDefaults: UserDefaults = {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }()

    /// Read by `CameraDetail` so the "Erweitert" section starts expanded (S3).
    nonisolated(unsafe) static var expandCameraAdvanced = false
    /// Read by `SoundTab` to show an error line (S5 empty-list variant).
    nonisolated(unsafe) static var soundTabError: String?
    /// Read by `SoundTab` as the voice of the selected entry (S5 voice variants).
    nonisolated(unsafe) static var soundTabVoice: PiperVoiceRef?
    /// Read by `SoundTab` as the draft text of the selected entry (S5 over-long text).
    nonisolated(unsafe) static var soundTabText: String?
    /// Read by `OnboardingTunnelStep` as its initial feedback line (Einrichtung step 6).
    /// Fixed sample strings only; no import runs and nothing touches the keychain in snapshot mode.
    nonisolated(unsafe) static var tunnelStepFeedback: ImportFeedback?
    /// Read by `TunnelSettingsView` instead of the live router/tunnel state (S6 variants).
    nonisolated(unsafe) static var tunnelPhase: TunnelPhase?
    /// Read by `SettingsRootView`: a taller window for renders that must show a whole tab (S2).
    nonisolated(unsafe) static var settingsHeight: CGFloat?

    /// Call first in `applicationDidFinishLaunching`; renders and terminates when requested.
    @MainActor
    static func runIfRequested() {
        guard let directory = outputDirectory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSApp.setActivationPolicy(.accessory)
        renderAll(into: directory)
        isolatedDefaults.removePersistentDomain(forName: suiteName)
        exit(0)
    }

    // MARK: Sample data

    private struct Sample {
        let settings: SettingsStore
        let door: WebhookMapping
        let garage: WebhookMapping
    }

    @MainActor
    private static func seed() -> Sample {
        let settings = SettingsStore.shared
        settings.protectHost = "192.168.1.1"
        settings.protectConsoleName = "UDM Pro"
        let actions = [
            CameraAction(id: UUID(), title: "Tür öffnen", url: "https://home.example/open", method: .post,
                         bearerToken: "", icon: .door, confirmBeforeRun: true),
            CameraAction(id: UUID(), title: "Flurlicht", url: "https://home.example/light", method: .get,
                         bearerToken: "", icon: .bulb, confirmBeforeRun: false),
            // Phase 5: a button that only plays an announcement.
            CameraAction(id: UUID(), title: "Gleich da", url: "", method: .post,
                         bearerToken: "", icon: .house, confirmBeforeRun: false, soundId: SoundSettings.bundledBinGleichDa.id),
        ]
        let rules = [
            EventRule(kind: "ring", webhook: EventRuleWebhook(method: "POST", url: "https://home.example/klingel"),
                      soundId: SoundSettings.bundledBinGleichDa.id),
            EventRule(kind: "package", soundId: SoundSettings.bundledPaket.id, delaySeconds: 20),
        ]
        let door = WebhookMapping(label: "Haustür", actions: actions, protectCameraId: "cam-door",
                                  triggers: [.ring, .person, .personLine], chimeOnOpen: true, eventRules: rules)
        let garage = WebhookMapping(label: "Garage", protectCameraId: "cam-garage", triggers: [.vehicle, .motion])
        let garden = WebhookMapping(label: "Garten", protectCameraId: "cam-garden", triggers: [.person, .animal])
        settings.mappings = [door, garage, garden]
        let cameraJSON = """
        [{"id":"cam-door","name":"Haustür","type":"UVC G4 Doorbell Pro","state":"CONNECTED","mac":"A1",
          "lcdMessage":{"type":"LEAVE_PACKAGE"},
          "featureFlags":{"hasSpeaker":true,"hasMic":true,"smartDetectTypes":["person","vehicle","package","animal"],"smartDetectAudioTypes":["alrmSpeak","alrmGlassBreak"]},
          "smartDetectSettings":{"objectTypes":["person","package"],"audioTypes":[]}},
         {"id":"cam-garage","name":"Garage","type":"UVC G5 Bullet","state":"CONNECTED","mac":"A2",
          "featureFlags":{"hasSpeaker":false,"hasMic":true,"smartDetectTypes":["person","vehicle"],"smartDetectAudioTypes":[]},
          "smartDetectSettings":{"objectTypes":["vehicle"],"audioTypes":[]}},
         {"id":"cam-garden","name":"Garten","type":"UVC G5 Flex","state":"CONNECTED","mac":"A3",
          "featureFlags":{"hasSpeaker":false,"hasMic":false,"smartDetectTypes":["person","animal"],"smartDetectAudioTypes":[]},
          "smartDetectSettings":{"objectTypes":["person","animal"],"audioTypes":[]}}]
        """
        if let cameras = try? JSONDecoder().decode([ProtectCamera].self, from: Data(cameraJSON.utf8)) {
            ProtectSession.shared.setSnapshotCameras(cameras)
        }
        settings.mute(entryId: garage.entryId, for: settings.muteShort)
        let now = Date()
        EventLog.shared.record(mapping: door, kindLabel: "Klingel", date: now.addingTimeInterval(-120))
        EventLog.shared.record(mapping: garden, kindLabel: "Person", date: now.addingTimeInterval(-3600))
        EventLog.shared.record(mapping: garage, kindLabel: "Fahrzeug", date: now.addingTimeInterval(-7200))
        // S5: sample announcements (SoundStore is isolated in snapshot mode: throwaway defaults and folder).
        SoundStore.shared.settings.announcements = SoundSettings.bundled + [
            Announcement(name: "Gong", kind: .file, fileName: "gong.mp3", duration: 12.4),
        ]
        return Sample(settings: settings, door: door, garage: garage)
    }

    // MARK: Rendering

    private static let appearances: [(name: String, appearance: NSAppearance.Name)] = [
        ("light", .aqua), ("dark", .darkAqua),
    ]

    @MainActor
    private static func renderAll(into directory: URL) {
        let sample = seed()
        let protectEvents = ProtectEventService()
        let relay = WebSocketClient()

        for (suffix, appearanceName) in appearances {
            let appearance = NSAppearance(named: appearanceName)!

            // S1 – S3, S5, S6: settings window (title bar included).
            func settingsWindow(tab: SettingsTab, entry: UUID? = nil) -> NSWindow {
                let navigation = SettingsNavigation()
                navigation.tab = tab
                navigation.selectedEntry = entry
                let root = SettingsRootView(navigation: navigation)
                    .environmentObject(sample.settings)
                    .environmentObject(relay)
                    .environmentObject(protectEvents)
                let window = SettingsWindowController.makeWindow(rootView: root)
                window.title = tab.windowTitle
                print("settings window \(tab.windowTitle): frame \(window.frame.size) content \(window.contentView?.frame.size ?? .zero)")
                return window
            }
            write(window: settingsWindow(tab: .general), appearance: appearance,
                  to: directory.appendingPathComponent("S1-allgemein-\(suffix).png"))
            // S2 tall enough for the whole camera page down to the „Ereignisse“ card.
            SnapshotRenderer.settingsHeight = 760
            let tallCameras = settingsWindow(tab: .cameras, entry: sample.door.entryId)
            tallCameras.setFrame(NSRect(x: 0, y: 0, width: 760, height: 760), display: false)
            write(window: tallCameras, appearance: appearance,
                  to: directory.appendingPathComponent("S2-kameras-\(suffix).png"))
            SnapshotRenderer.settingsHeight = nil
            expandCameraAdvanced = true
            write(window: settingsWindow(tab: .cameras, entry: sample.door.entryId), appearance: appearance,
                  to: directory.appendingPathComponent("S3-kameras-erweitert-\(suffix).png"))
            expandCameraAdvanced = false
            write(window: settingsWindow(tab: .sound), appearance: appearance,
                  to: directory.appendingPathComponent("S5-ton-\(suffix).png"))
            // S5 variant: empty list with an error line below the links.
            let savedSounds = SoundStore.shared.settings.announcements
            SoundStore.shared.settings.announcements = []
            SnapshotRenderer.soundTabError = "Die Datei ist länger als 5 Minuten."
            write(window: settingsWindow(tab: .sound), appearance: appearance,
                  to: directory.appendingPathComponent("S5-ton-leer-fehler-\(suffix).png"))
            SnapshotRenderer.soundTabError = nil
            SoundStore.shared.settings.announcements = savedSounds
            // Phase 6 (no voice bundled): S5-ton above shows the default Thorsten not downloaded yet.
            // Now a voice that is not downloaded yet, loading, next to downloaded ones.
            SnapshotRenderer.soundTabVoice = PiperVoiceRef(voiceId: "de_DE-kerstin-low")
            PiperVoiceStore.shared.simulateDownloaded(["de_DE-thorsten-medium", "de_DE-thorsten-high"])
            write(window: settingsWindow(tab: .sound), appearance: appearance,
                  to: directory.appendingPathComponent("S5-ton-stimme-nicht-geladen-\(suffix).png"))
            PiperVoiceStore.shared.simulateDownload("de_DE-kerstin-low", received: 23_400_000)
            write(window: settingsWindow(tab: .sound), appearance: appearance,
                  to: directory.appendingPathComponent("S5-ton-stimme-laedt-\(suffix).png"))
            PiperVoiceStore.shared.simulateDownload("de_DE-kerstin-low", received: nil)
            // Multi-speaker voice: second field with the speaker.
            SnapshotRenderer.soundTabVoice = PiperVoiceRef(voiceId: "de_DE-thorsten_emotional-medium", speaker: 4)
            write(window: settingsWindow(tab: .sound), appearance: appearance,
                  to: directory.appendingPathComponent("S5-ton-sprecher-\(suffix).png"))
            SnapshotRenderer.soundTabVoice = nil
            // Text above the 1000-character limit (counter orange, „Anhören“/„Übernehmen“ off) while
            // Piper speaks with Thorsten · hoch („Entfernen“ off).
            SnapshotRenderer.soundTabText = String(repeating: "Bitte das Paket vor der Garage abstellen. ", count: 30)
            PiperVoiceStore.shared.simulateRendering("de_DE-thorsten-high")
            write(window: settingsWindow(tab: .sound), appearance: appearance,
                  to: directory.appendingPathComponent("S5-ton-zu-lang-\(suffix).png"))
            SnapshotRenderer.soundTabText = nil
            PiperVoiceStore.shared.simulateRendering(nil)
            PiperVoiceStore.shared.simulateDownloaded([])
            // An announcement rendered by a macOS voice before Phase 6, with a Piper error line.
            SoundStore.shared.settings.announcements = [
                Announcement(name: "Bitte warten", kind: .speech, text: "Bitte einen Moment warten.",
                             voiceIdentifier: "com.apple.voice.premium.de-DE.Anna", fileName: "alt.caf", duration: 2.1),
            ] + savedSounds
            SnapshotRenderer.soundTabError = PiperError.timeout(20).errorDescription
            write(window: settingsWindow(tab: .sound), appearance: appearance,
                  to: directory.appendingPathComponent("S5-ton-macos-alt-\(suffix).png"))
            SnapshotRenderer.soundTabError = nil
            SoundStore.shared.settings.announcements = savedSounds
            // S6: the real tab in its states (sample records only; nothing is persisted).
            let sampleSummary = TunnelConfigSummary(endpoint: "vpn.example.net:51820")
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            let connected = TunnelRecord(fileName: "macbook-camera-popup.conf", summary: sampleSummary,
                                         lastConnection: TunnelLastConnection(date: yesterday, via: .cellular))
            let remoteStates: [(name: String, record: TunnelRecord, phase: TunnelPhase?)] = [
                ("leer", TunnelRecord(), nil),
                ("verbunden", connected, .connected),
                ("zuhause", connected, .home),
                ("fehler", connected, .failed("Die Gegenstelle konnte nicht aufgelöst werden.")),
            ]
            for state in remoteStates {
                TunnelStore.shared.snapshotSeed(state.record)
                SnapshotRenderer.tunnelPhase = state.phase
                let name = state.name == "zuhause" ? "S6-unterwegs-\(suffix).png" : "S6-unterwegs-\(state.name)-\(suffix).png"
                write(window: settingsWindow(tab: .remote), appearance: appearance,
                      to: directory.appendingPathComponent(name))
            }
            SnapshotRenderer.tunnelPhase = nil
            TunnelStore.shared.snapshotSeed(TunnelRecord())

            // Einrichtung step 6 "Unterwegs": empty drop zone, after import, warning, error.
            let tunnelStates: [(name: String, feedback: ImportFeedback?)] = [
                ("leer", nil),
                ("importiert", .imported(endpoint: "vpn.example.net:51820", warning: nil)),
                ("warnung", .imported(endpoint: "vpn.example.net:51820",
                                      warning: "Achtung: Konsole 192.168.1.1 liegt nicht in „AllowedIPs“.")),
                ("fehler", .failed("Keine gültige WireGuard-Datei: Es fehlt der Abschnitt [Peer].")),
            ]
            for state in tunnelStates {
                tunnelStepFeedback = state.feedback
                let onboarding = OnboardingModel()
                onboarding.step = .travel
                let host = NSHostingController(rootView: OnboardingView(model: onboarding))
                let onboardingWindow = NSWindow(contentViewController: host)
                onboardingWindow.title = "Camera Popup einrichten"
                onboardingWindow.styleMask = [.titled, .closable, .fullSizeContentView]
                onboardingWindow.titlebarAppearsTransparent = true
                onboardingWindow.setContentSize(NSSize(width: 560, height: 420))
                write(window: onboardingWindow, appearance: appearance,
                      to: directory.appendingPathComponent("E6-unterwegs-\(state.name)-\(suffix).png"))
            }
            tunnelStepFeedback = nil

            // S4 – button sheet. A sheet needs an on-screen window, so it is composed over a dimmed Kameras tab.
            let navigation = SettingsNavigation()
            navigation.tab = .cameras
            navigation.selectedEntry = sample.door.entryId
            let sheetRoot = ZStack {
                SettingsRootView(navigation: navigation)
                Color.black.opacity(0.3).frame(width: 760, height: 540)
                ActionEditorSheet(
                    action: sample.door.actions[0], isNew: false,
                    sounds: SoundStore.shared.settings.announcements, canPlaySound: true,
                    onSave: { _ in }, onDelete: {}
                )
                    .background(Tokens.win.color)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .environmentObject(sample.settings)
            .environmentObject(relay)
            .environmentObject(protectEvents)
            let sheetWindow = SettingsWindowController.makeWindow(rootView: sheetRoot)
            sheetWindow.title = "Kameras"
            write(window: sheetWindow, appearance: appearance,
                  to: directory.appendingPathComponent("S4-button-sheet-\(suffix).png"))

            // Phase 5: event rule sheet over the same dimmed Kameras tab.
            let ruleRoot = ZStack {
                SettingsRootView(navigation: navigation)
                Color.black.opacity(0.3).frame(width: 760, height: 540)
                EventRuleEditorSheet(
                    rule: sample.door.eventRules[0], isNew: false,
                    kinds: [.ring, .person, .package, .animal, .vehicle, .motion],
                    sounds: SoundStore.shared.settings.announcements, canPlaySound: true,
                    onSave: { _ in }, onDelete: {}
                )
                .background(Tokens.win.color)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .environmentObject(sample.settings)
            .environmentObject(relay)
            .environmentObject(protectEvents)
            let ruleWindow = SettingsWindowController.makeWindow(rootView: ruleRoot)
            ruleWindow.title = "Kameras"
            write(window: ruleWindow, appearance: appearance,
                  to: directory.appendingPathComponent("S4-regel-sheet-\(suffix).png"))

            // Proof for the chip outline: same chips via ImageRenderer (no AppKit cacheDisplay).
            if let camera = ProtectSession.shared.cameras.first {
                let chips = TriggerChips(camera: camera, selection: .constant([.ring, .person]), size: .small)
                    .padding(10).frame(width: 420)
                    .background(Tokens.win.color)
                    .environment(\.colorScheme, suffix == "dark" ? .dark : .light)
                let renderer = ImageRenderer(content: chips)
                renderer.scale = 2
                if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: directory.appendingPathComponent("chips-imagerenderer-\(suffix).png"))
                }
            }

            // 7 – menu panel.
            let panel = StatusPanelView(
                settings: sample.settings, events: EventLog.shared, protectEvents: protectEvents,
                relay: relay, protect: ProtectSession.shared, clock: StatusPanelClock(), updates: UpdateService(),
                actions: StatusPanelActions(openSettings: {}, openHelp: {}, quit: {}, openCamera: { _ in },
                                            installUpdate: {}, close: {}, resize: { _ in })
            )
            let panelHost = NSHostingView(rootView: panel)
            let panelSize = panelHost.fittingSize
            panelHost.frame = NSRect(origin: .zero, size: CGSize(width: 338, height: panelSize.height))
            let panelWindow = NSWindow(contentRect: panelHost.frame, styleMask: [.borderless],
                                       backing: .buffered, defer: false)
            panelWindow.backgroundColor = .clear
            panelWindow.contentView = panelHost
            write(window: panelWindow, appearance: appearance, includeFrame: false,
                  to: directory.appendingPathComponent("7-panel-\(suffix).png"))

            // 7 – menu panel with an available update (Phase 5).
            let updates = UpdateService()
            let manifestJSON = #"{"versionId":"x","buildNumber":30,"shortVersion":"1.3.0","url":"https://example.invalid/app.zip","sha256":"","signature":"s"}"#
            if let manifest = try? JSONDecoder().decode(UpdateManifest.self, from: Data(manifestJSON.utf8)) {
                updates.debugApply(state: .available(buildNumber: 30, shortVersion: "1.3.0"), manifest: manifest)
            }
            let updatePanel = NSHostingView(rootView: StatusPanelView(
                settings: sample.settings, events: EventLog.shared, protectEvents: protectEvents,
                relay: relay, protect: ProtectSession.shared, clock: StatusPanelClock(), updates: updates,
                actions: StatusPanelActions(openSettings: {}, openHelp: {}, quit: {}, openCamera: { _ in },
                                            installUpdate: {}, close: {}, resize: { _ in })
            ))
            updatePanel.frame = NSRect(origin: .zero, size: CGSize(width: 338, height: updatePanel.fittingSize.height))
            let updateWindow = NSWindow(contentRect: updatePanel.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            updateWindow.backgroundColor = .clear
            updateWindow.contentView = updatePanel
            write(window: updateWindow, appearance: appearance, includeFrame: false,
                  to: directory.appendingPathComponent("7-panel-update-\(suffix).png"))

            // 8 – popup chrome, mute menu closed and open; Phase 5 default: no chip.
            let plain = PopupWindow(
                frame: NSRect(x: 0, y: 0, width: 470, height: 300),
                streamURL: "", soundEnabled: false,
                thumbnailDataURI: placeholderDataURI(size: CGSize(width: 470, height: 300)),
                autoCloseSeconds: 0,
                actions: Array(sample.door.actions.prefix(2)),
                overlay: PopupOverlayContent(
                    chip: nil, cameraName: "Haustür",
                    muteOptions: sample.settings.muteOptions, onMute: { _ in },
                    sound: PopupSoundContent(enabled: false) { _ in }
                ),
                onClose: {}
            )
            write(window: plain, appearance: appearance, includeFrame: false,
                  to: directory.appendingPathComponent("8-popup-ohne-chip-\(suffix).png"))
            for menuOpen in [false, true] {
                let popup = PopupWindow(
                    frame: NSRect(x: 0, y: 0, width: 470, height: 300),
                    streamURL: "", soundEnabled: false,
                    thumbnailDataURI: placeholderDataURI(size: CGSize(width: 470, height: 300)),
                    autoCloseSeconds: 0,
                    actions: Array(sample.door.actions.prefix(2)),
                    overlay: PopupOverlayContent(
                        chip: { _ in "Klingel · Haustür · 10:41:07" }, cameraName: "Haustür",
                        muteOptions: sample.settings.muteOptions, onMute: { _ in }
                    ),
                    onClose: {}
                )
                if menuOpen { popup.perform(NSSelectorFromString("muteTapped")) }
                write(window: popup, appearance: appearance, includeFrame: false,
                      to: directory.appendingPathComponent("8-popup\(menuOpen ? "-menue" : "")-\(suffix).png"))
            }

            // 9 – popup with "Ton abspielen" / "Sprechen": idle, announcement menu, connecting, talking, playing, notice.
            let doorId = sample.door.entryId
            let notice = TalkbackNotice(entryId: doorId, text: "Kein Zugriff aufs Mikrofon. Erlaube den Zugriff in den Systemeinstellungen unter Datenschutz & Sicherheit.")
            let talkStates: [(name: String, activity: TalkbackActivity?, notice: TalkbackNotice?, openMenu: Bool)] = [
                ("ruhe", nil, nil, false),
                ("menue", nil, nil, true),
                ("verbinde", TalkbackActivity(entryId: doorId, purpose: .talk, phase: .preparing), nil, false),
                ("spricht", TalkbackActivity(entryId: doorId, purpose: .talk, phase: .live), nil, false),
                ("ansage", TalkbackActivity(entryId: doorId, purpose: .announcement(UUID()), phase: .live), nil, false),
                ("hinweis", nil, notice, false),
            ]
            for state in talkStates {
                TalkbackService.shared.debugApply(activity: state.activity, notice: nil)
                let popup = PopupWindow(
                    frame: NSRect(x: 0, y: 0, width: 470, height: 300),
                    streamURL: "", soundEnabled: false,
                    thumbnailDataURI: placeholderDataURI(size: CGSize(width: 470, height: 300)),
                    autoCloseSeconds: 0,
                    actions: sample.door.actions,
                    overlay: PopupOverlayContent(
                        chip: { _ in "Klingel · Haustür · 10:41:07" }, cameraName: "Haustür",
                        muteOptions: sample.settings.muteOptions, onMute: { _ in },
                        talk: PopupTalkContent(entryId: doorId),
                        sound: PopupSoundContent(enabled: true) { _ in }
                    ),
                    onClose: {}
                )
                if state.openMenu, let content = popup.contentView {
                    func find(_ view: NSView) -> CircleIconButton? {
                        if let button = view as? CircleIconButton, button.toolTip == "Ansage abspielen" { return button }
                        for sub in view.subviews { if let hit = find(sub) { return hit } }
                        return nil
                    }
                    find(content)?.performClick(nil)
                }
                if let shown = state.notice {
                    TalkbackService.shared.debugApply(activity: state.activity, notice: shown)
                }
                write(window: popup, appearance: appearance, includeFrame: false,
                      to: directory.appendingPathComponent("9-popup-sprechen-\(state.name)-\(suffix).png"))
                TalkbackService.shared.debugApply(activity: nil, notice: nil)
            }

            // 9 – smallest stacked popup (160 high, 16:9): talk button shrinks to the microphone (Phase 5).
            let narrow = PopupWindow(
                frame: NSRect(x: 0, y: 0, width: 284, height: 160),
                streamURL: "", soundEnabled: false,
                thumbnailDataURI: placeholderDataURI(size: CGSize(width: 284, height: 160)),
                autoCloseSeconds: 0,
                actions: sample.door.actions,
                overlay: PopupOverlayContent(
                    chip: nil, cameraName: "Haustür",
                    muteOptions: sample.settings.muteOptions, onMute: { _ in },
                    talk: PopupTalkContent(entryId: doorId),
                        sound: PopupSoundContent(enabled: true) { _ in }
                ),
                onClose: {}
            )
            write(window: narrow, appearance: appearance, includeFrame: false,
                  to: directory.appendingPathComponent("9-popup-schmal-\(suffix).png"))
        }
    }

    /// Renders the window's frame view (title bar included) or just its content at 2× into a PNG.
    @MainActor
    private static func write(window: NSWindow, appearance: NSAppearance, includeFrame: Bool = true, to url: URL) {
        window.appearance = appearance
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.contentView?.layoutSubtreeIfNeeded()
        // Let SwiftUI resolve @State, .task and preference updates.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        guard let content = window.contentView else { return }
        let view: NSView = includeFrame ? (content.superview ?? content) : content
        view.layoutSubtreeIfNeeded()
        let size = view.bounds.size
        print("render \(url.lastPathComponent): window \(window.frame.size) frameView \(view.bounds.size)")
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
    }

    /// Gradient stand-in for the camera picture.
    @MainActor
    private static func placeholderDataURI(size: CGSize) -> String? {
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(calibratedRed: 0.35, green: 0.45, blue: 0.40, alpha: 1),
                                NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.20, alpha: 1)])?
                .draw(in: rect, angle: 60)
            return true
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }
}
#endif
