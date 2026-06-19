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

    /// Lays out several popups in a vertical stack anchored at `position`. The
    /// first entry sits at the anchor; subsequent entries are placed beneath it
    /// (or above it for bottom anchors so the stack stays on screen). Horizontal
    /// alignment for each popup matches the single-popup placement for its size,
    /// preserving the order of `sizes`.
    static func stackedFrames(
        sizes: [CGSize],
        position: PopupPosition,
        margin: CGFloat,
        screen: NSScreen,
        gap: CGFloat = 12
    ) -> [NSRect] {
        guard !sizes.isEmpty else { return [] }

        let baseFrames = sizes.map {
            frame(width: $0.width, height: $0.height, position: position, margin: margin, screen: screen)
        }

        var result: [NSRect] = []
        result.reserveCapacity(sizes.count)

        if position.stacksUpward {
            var bottom = baseFrames[0].minY
            for (index, size) in sizes.enumerated() {
                result.append(NSRect(x: baseFrames[index].minX, y: bottom, width: size.width, height: size.height))
                bottom += size.height + gap
            }
        } else {
            var top = baseFrames[0].maxY
            for (index, size) in sizes.enumerated() {
                let originY = top - size.height
                result.append(NSRect(x: baseFrames[index].minX, y: originY, width: size.width, height: size.height))
                top = originY - gap
            }
        }

        return result
    }
}
