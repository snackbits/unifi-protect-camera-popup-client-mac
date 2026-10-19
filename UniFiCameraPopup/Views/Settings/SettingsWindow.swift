import AppCore
import AppKit
import Combine
import SwiftUI

enum SettingsTab: Int, CaseIterable, Identifiable {
    case general
    case appearance
    case cameras
    case sound
    case remote

    var id: Int { rawValue }

    /// Tab button text.
    var label: String {
        switch self {
        case .general: return "Allgemein"
        case .appearance: return "Erscheinungsbild"
        case .cameras: return "Kameras"
        case .sound: return "Ton"
        case .remote: return "Unterwegs"
        }
    }

    /// Window title while the tab is shown (template title bar).
    var windowTitle: String {
        switch self {
        case .general: return "Allgemein"
        case .appearance: return "Erscheinungsbild"
        case .cameras: return "Kameras"
        case .sound: return "Ton & Sprechen"
        case .remote: return "Unterwegs"
        }
    }

    var icon: TemplateIcon {
        switch self {
        case .general: return .tabGeneral
        case .appearance: return .tabAppearance
        case .cameras: return .tabCameras
        case .sound: return .tabSound
        case .remote: return .tabRemote
        }
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .general
    /// Camera selected in the Kameras tab (mapping entry id).
    @Published var selectedEntry: UUID?
}

/// Entry points owned by `AppDelegate` that SwiftUI views call
/// (with `@NSApplicationDelegateAdaptor`, `NSApp.delegate` is not our instance).
@MainActor
enum AppActions {
    static var openHelp: () -> Void = {}
    /// Einstellungen › Kameras with this entry selected (gear in the popup).
    static var openCameraSettings: (UUID) -> Void = { _ in }
}

/// Fixed 760 × 540 window with transparent title bar; the tab bar is drawn below it.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    let navigation = SettingsNavigation()
    private var window: NSWindow?
    private var titleObserver: AnyCancellable?

    private init() {}

    /// Template window: 760 × 540 in total, title bar included (content runs under the transparent title bar).
    static func makeWindow<Root: View>(rootView: Root) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        // A hosting view as `contentView` resizes the window to its ideal height (540 + title bar = 572).
        // Wrapped in a plain container the window keeps the template size.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 540))
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        window.contentView = container
        // `contentRect` excludes the title bar; pin the whole frame to the template size.
        window.setFrame(NSRect(x: 0, y: 0, width: 760, height: 540), display: false)
        return window
    }

    func show(webSocketClient: WebSocketClient, protectEvents: ProtectEventService, tab: SettingsTab? = nil) {
        if let tab {
            navigation.tab = tab
        }
        if window == nil {
            let root = SettingsRootView(navigation: navigation)
                .environmentObject(SettingsStore.shared)
                .environmentObject(webSocketClient)
                .environmentObject(protectEvents)
            let window = Self.makeWindow(rootView: root)
            window.title = navigation.tab.windowTitle
            window.center()
            titleObserver = navigation.$tab.sink { [weak window] tab in
                window?.title = tab.windowTitle
            }
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsRootView: View {
    @ObservedObject var navigation: SettingsNavigation

    private static var height: CGFloat {
        #if DEBUG
        SnapshotRenderer.settingsHeight ?? 540
        #else
        540
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                // Native title bar (traffic lights + centered title) sits on top of this.
                Color.clear.frame(height: 28)
                SettingsTabBar(selection: $navigation.tab)
            }
            .background(Tokens.bar.color)
            CardDivider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 760, height: Self.height)
        .background(Tokens.win.color)
        .foregroundStyle(Tokens.fg.color)
        .font(.system(size: 13))
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        switch navigation.tab {
        case .general: GeneralTab()
        case .appearance: AppearanceTab()
        case .cameras: CamerasTab(navigation: navigation)
        case .sound: SoundTab()
        case .remote: RemoteTab()
        }
    }
}

/// Centered tab buttons: at least 78 wide (longer labels: padding 10), padding 5, radius 7, icon 20 + 3 + label 11.
struct SettingsTabBar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                let isOn = tab == selection
                Button { selection = tab } label: {
                    VStack(spacing: 3) {
                        tab.icon.image(size: 20)
                        Text(tab.label).font(.system(size: 11)).lineLimit(1).fixedSize()
                    }
                    .foregroundStyle(isOn ? Tokens.accText.color : Tokens.muted.color)
                    // Longer labels („Erscheinungsbild“) widen the button: padding 10 as in the mock.
                    .padding(.horizontal, 10)
                    .frame(minWidth: 78)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(isOn ? Tokens.tabOn.color : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }
}
