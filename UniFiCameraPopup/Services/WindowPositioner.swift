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

    static func frame(
        width: CGFloat,
        height: CGFloat,
        position: PopupPosition,
        margin: CGFloat,
        screen: NSScreen
    ) -> NSRect {
        let visible = screen.visibleFrame
        let size = NSSize(width: width, height: height)
        var origin = NSPoint.zero

        switch position {
        case .topLeft:
            origin = NSPoint(
                x: visible.minX + margin,
                y: visible.maxY - margin - height
            )
        case .topCenter:
            origin = NSPoint(
                x: visible.midX - width / 2,
                y: visible.maxY - margin - height
            )
        case .topRight:
            origin = NSPoint(
                x: visible.maxX - margin - width,
                y: visible.maxY - margin - height
            )
        case .middleLeft:
            origin = NSPoint(
                x: visible.minX + margin,
                y: visible.midY - height / 2
            )
        case .center:
            origin = NSPoint(
                x: visible.midX - width / 2,
                y: visible.midY - height / 2
            )
        case .middleRight:
            origin = NSPoint(
                x: visible.maxX - margin - width,
                y: visible.midY - height / 2
            )
        case .bottomLeft:
            origin = NSPoint(
                x: visible.minX + margin,
                y: visible.minY + margin
            )
        case .bottomCenter:
            origin = NSPoint(
                x: visible.midX - width / 2,
                y: visible.minY + margin
            )
        case .bottomRight:
            origin = NSPoint(
                x: visible.maxX - margin - width,
                y: visible.minY + margin
            )
        }

        return NSRect(origin: origin, size: size)
    }
}
