import AppKit

/// Interactive crop rectangle overlay. Users draw a new region or resize/move an
/// existing one via corner and edge handles.
final class CropSelectionView: NSView {
    private enum Handle {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    private enum DragMode {
        case none
        case creating(start: NSPoint)
        case moving(start: NSPoint, rect: CGRect)
        case resizing(handle: Handle, rect: CGRect)
    }

    private static let handleSize: CGFloat = 10
    private static let minCropSize: CGFloat = 40

    private(set) var cropRect: CGRect = .zero
    private var dragMode: DragMode = .none

    var hasValidSelection: Bool {
        cropRect.width >= Self.minCropSize && cropRect.height >= Self.minCropSize
    }

    var onSelectionChanged: (() -> Void)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard hasValidSelection else { return }

        let path = NSBezierPath(rect: bounds)
        path.appendRect(cropRect)
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.45).setFill()
        path.fill()

        NSColor.white.setStroke()
        let border = NSBezierPath(rect: cropRect)
        border.lineWidth = 2
        border.stroke()

        drawHandles()
    }

    private func drawHandles() {
        NSColor.white.setFill()
        for handle in allHandles {
            let rect = handleRect(for: handle)
            NSBezierPath(ovalIn: rect).fill()
            NSColor.black.withAlphaComponent(0.6).setStroke()
            let outline = NSBezierPath(ovalIn: rect)
            outline.lineWidth = 1
            outline.stroke()
        }
    }

    private var allHandles: [Handle] {
        [.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left]
    }

    private func handleRect(for handle: Handle) -> CGRect {
        let size = Self.handleSize
        let half = size / 2
        let r = cropRect
        switch handle {
        case .topLeft:
            return CGRect(x: r.minX - half, y: r.minY - half, width: size, height: size)
        case .top:
            return CGRect(x: r.midX - half, y: r.minY - half, width: size, height: size)
        case .topRight:
            return CGRect(x: r.maxX - half, y: r.minY - half, width: size, height: size)
        case .right:
            return CGRect(x: r.maxX - half, y: r.midY - half, width: size, height: size)
        case .bottomRight:
            return CGRect(x: r.maxX - half, y: r.maxY - half, width: size, height: size)
        case .bottom:
            return CGRect(x: r.midX - half, y: r.maxY - half, width: size, height: size)
        case .bottomLeft:
            return CGRect(x: r.minX - half, y: r.maxY - half, width: size, height: size)
        case .left:
            return CGRect(x: r.minX - half, y: r.midY - half, width: size, height: size)
        }
    }

    private func handle(at point: NSPoint) -> Handle? {
        for handle in allHandles where handleRect(for: handle).contains(point) {
            return handle
        }
        return nil
    }

    override func resetCursorRects() {
        guard hasValidSelection else { return }
        for handle in allHandles {
            addCursorRect(handleRect(for: handle), cursor: cursor(for: handle))
        }
        if cropRect.contains(convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)) {
            addCursorRect(cropRect, cursor: .openHand)
        }
    }

    private func cursor(for handle: Handle) -> NSCursor {
        switch handle {
        case .topLeft, .bottomRight: return .crosshair
        case .topRight, .bottomLeft: return .crosshair
        case .top, .bottom: return .resizeUpDown
        case .left, .right: return .resizeLeftRight
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if let handle = handle(at: point), hasValidSelection {
            dragMode = .resizing(handle: handle, rect: cropRect)
            return
        }

        if hasValidSelection, cropRect.contains(point) {
            dragMode = .moving(start: point, rect: cropRect)
            return
        }

        dragMode = .creating(start: point)
        cropRect = CGRect(origin: point, size: .zero)
        needsDisplay = true
        onSelectionChanged?()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clamped = clampPoint(point)

        switch dragMode {
        case .none:
            break
        case .creating(let start):
            cropRect = normalizedRect(from: start, to: clamped)
            needsDisplay = true
            onSelectionChanged?()
        case .moving(let start, let original):
            let dx = clamped.x - start.x
            let dy = clamped.y - start.y
            cropRect = clampRect(original.offsetBy(dx: dx, dy: dy))
            needsDisplay = true
            onSelectionChanged?()
        case .resizing(let handle, let original):
            cropRect = clampRect(resizeRect(original, handle: handle, to: clamped))
            needsDisplay = true
            onSelectionChanged?()
        }
    }

    override func mouseUp(with event: NSEvent) {
        if case .creating = dragMode, !hasValidSelection {
            cropRect = .zero
            needsDisplay = true
            onSelectionChanged?()
        }
        dragMode = .none
        resetCursorRects()
    }

    private func normalizedRect(from start: NSPoint, to end: NSPoint) -> CGRect {
        let x = min(start.x, end.x)
        let y = min(start.y, end.y)
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)
        return clampRect(CGRect(x: x, y: y, width: width, height: height))
    }

    private func resizeRect(_ rect: CGRect, handle: Handle, to point: NSPoint) -> CGRect {
        var r = rect
        switch handle {
        case .topLeft:
            r.origin.x = point.x
            r.origin.y = point.y
            r.size.width = rect.maxX - point.x
            r.size.height = rect.maxY - point.y
        case .top:
            r.origin.y = point.y
            r.size.height = rect.maxY - point.y
        case .topRight:
            r.origin.y = point.y
            r.size.width = point.x - rect.minX
            r.size.height = rect.maxY - point.y
        case .right:
            r.size.width = point.x - rect.minX
        case .bottomRight:
            r.size.width = point.x - rect.minX
            r.size.height = point.y - rect.minY
        case .bottom:
            r.size.height = point.y - rect.minY
        case .bottomLeft:
            r.origin.x = point.x
            r.size.width = rect.maxX - point.x
            r.size.height = point.y - rect.minY
        case .left:
            r.origin.x = point.x
            r.size.width = rect.maxX - point.x
        }
        return r
    }

    private func clampPoint(_ point: NSPoint) -> NSPoint {
        NSPoint(
            x: min(max(point.x, 0), bounds.width),
            y: min(max(point.y, 0), bounds.height)
        )
    }

    private func clampRect(_ rect: CGRect) -> CGRect {
        var r = rect
        if r.width < 0 {
            r.origin.x += r.width
            r.size.width = abs(r.width)
        }
        if r.height < 0 {
            r.origin.y += r.height
            r.size.height = abs(r.height)
        }

        r.origin.x = max(0, r.origin.x)
        r.origin.y = max(0, r.origin.y)
        if r.maxX > bounds.width {
            r.size.width = bounds.width - r.origin.x
        }
        if r.maxY > bounds.height {
            r.size.height = bounds.height - r.origin.y
        }
        return r
    }

    /// Converts the selection to normalized coordinates (bottom-left origin, matching AppKit).
    func normalizedCrop() -> CameraCrop? {
        guard hasValidSelection, bounds.width > 0, bounds.height > 0 else { return nil }
        let normalizedY = (bounds.height - cropRect.maxY) / bounds.height
        return CameraCrop(
            x: Double(cropRect.origin.x / bounds.width),
            y: Double(normalizedY),
            width: Double(cropRect.width / bounds.width),
            height: Double(cropRect.height / bounds.height),
            originalWidth: 0,
            originalHeight: 0
        )
    }

    /// Pixel dimensions of the current selection.
    var selectionPixelSize: CGSize {
        CGSize(width: cropRect.width, height: cropRect.height)
    }
}
