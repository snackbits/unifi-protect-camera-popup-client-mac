import AppKit

enum WindowPositioner {
    static func targetScreen(for target: ScreenTarget) -> NSScreen {
        switch target {
        case .main:
            return NSScreen.main ?? NSScreen.screens.first!
        case .mouse:
            let mouseLocation = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
                ?? NSScreen.main
                ?? NSScreen.screens.first!
        }
    }
}
