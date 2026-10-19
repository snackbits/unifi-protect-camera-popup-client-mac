import CoreGraphics
import Foundation

/// "Kamera › Größe": empty fields mean automatic. A single value keeps the aspect ratio.
public struct PopupSizeOverride: Codable, Equatable, Sendable {
    public var width: Double?
    public var height: Double?

    public static let automatic = PopupSizeOverride()
    /// The size every camera had before Phase 5 unless the user changed it.
    public static let legacyDefault = CGSize(width: 480, height: 270)
    /// Smallest popup side a typed value results in (applied by `PopupSizing`, not while typing).
    public static let minimumValue = 40.0

    public init(width: Double? = nil, height: Double? = nil) {
        self.width = Self.valid(width)
        self.height = Self.valid(height)
    }

    public var isAutomatic: Bool { width == nil && height == nil }

    /// Pre-Phase-5 entries: 480 × 270 counts as "never changed" (automatic), anything else is kept.
    public static func migrated(width: Double, height: Double) -> PopupSizeOverride {
        if width == Double(legacyDefault.width), height == Double(legacyDefault.height) { return .automatic }
        return PopupSizeOverride(width: width, height: height)
    }

    /// Text of a size field → value: digits only (at most 5), empty or 0 = automatic (nil).
    public static func value(fromText text: String) -> Double? {
        let digits = text.filter(\.isASCIIDigitCharacter)
        guard !digits.isEmpty, let parsed = Double(digits.prefix(5)), parsed > 0 else { return nil }
        return parsed
    }

    private static func valid(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private enum CodingKeys: String, CodingKey { case width, height }

    /// Lenient: a broken value counts as empty (automatic).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            width: (try? c.decodeIfPresent(Double.self, forKey: .width)) ?? nil,
            height: (try? c.decodeIfPresent(Double.self, forKey: .height)) ?? nil
        )
    }
}

private extension Character {
    var isASCIIDigitCharacter: Bool { isASCII && isNumber }
}

/// Size a camera popup asks for before stacking (Phase 5 default: 42 % of the visible height).
public enum PopupSizing {
    public static let automaticHeightShare = 0.42
    public static let defaultAspect = 16.0 / 9.0

    /// `aspect` = width / height (crop, camera picture or nil → 16:9). Automatic sizes also fit
    /// the visible width minus both margins.
    public static func size(
        override: PopupSizeOverride,
        aspect: Double?,
        visible: CGSize,
        margin: CGFloat
    ) -> CGSize {
        let ratio = validAspect(aspect)
        let minimum = PopupSizeOverride.minimumValue
        switch (override.width.map { max(minimum, $0) }, override.height.map { max(minimum, $0) }) {
        case let (width?, height?):
            return CGSize(width: width, height: height)
        case let (width?, nil):
            return CGSize(width: width, height: (width / ratio).rounded())
        case let (nil, height?):
            return CGSize(width: (height * ratio).rounded(), height: height)
        case (nil, nil):
            var height = Double(visible.height) * automaticHeightShare
            var width = height * ratio
            let maxWidth = max(Double(visible.width - 2 * margin), 1)
            if width > maxWidth {
                width = maxWidth
                height = width / ratio
            }
            return CGSize(width: width.rounded(), height: height.rounded())
        }
    }

    public static func validAspect(_ aspect: Double?) -> Double {
        guard let aspect, aspect.isFinite, aspect > 0.2, aspect < 5 else { return defaultAspect }
        return aspect
    }
}

/// Where the popup stack sits (the app's `PopupPosition` uses only the two top anchors).
public struct PopupAnchor: Equatable, Sendable {
    public enum Horizontal: Sendable { case leading, center, trailing }
    public enum Vertical: Sendable { case top, middle, bottom }

    public let horizontal: Horizontal
    public let vertical: Vertical

    public init(horizontal: Horizontal, vertical: Vertical) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
}

public extension PopupAnchor.Horizontal {
    /// Stored `PopupPosition` value → side. Builds before the two-sided position had nine anchors:
    /// `topLeft`, `middleLeft` and `bottomLeft` become left, every other (also unknown) value right.
    static func side(fromPositionRawValue raw: String) -> PopupAnchor.Horizontal {
        switch raw {
        case "left", "topLeft", "middleLeft", "bottomLeft": return .leading
        default: return .trailing
        }
    }
}

/// Lays out all open popups so that every one is fully visible: one uniform scale factor
/// (aspect ratios stay), never larger than asked for, at least `minimumHeight` per popup where
/// possible – otherwise further columns next to the first. Coordinates are AppKit screen
/// coordinates (y up); the result keeps the order of `sizes` (first = at the anchor).
public enum PopupStackLayout {
    public static let gap: CGFloat = 12
    public static let minimumHeight: CGFloat = 160

    public static func frames(
        sizes: [CGSize],
        anchor: PopupAnchor,
        visible: CGRect,
        margin: CGFloat,
        gap: CGFloat = PopupStackLayout.gap,
        minimumHeight: CGFloat = PopupStackLayout.minimumHeight
    ) -> [CGRect] {
        guard !sizes.isEmpty else { return [] }
        let area = visible.insetBy(dx: min(margin, visible.width / 2), dy: min(margin, visible.height / 2))
        let sizes = sizes.map { CGSize(width: max($0.width, 1), height: max($0.height, 1)) }

        // Fewest columns whose scale keeps every popup at its minimum; else the largest scale.
        var best: (columns: [[Int]], scale: CGFloat)?
        for count in 1...sizes.count {
            let columns = split(sizes.indices.map { $0 }, into: count)
            let s = scale(columns: columns, sizes: sizes, area: area.size, gap: gap)
            let keepsMinimum = s >= 1 || sizes.allSatisfy { $0.height * s >= min($0.height, minimumHeight) - 0.5 }
            if keepsMinimum {
                best = (columns, s)
                break
            }
            if best == nil || s > best!.scale + 0.0001 {
                best = (columns, s)
            }
        }
        guard let (columns, s) = best else { return [] }
        return place(columns: columns, sizes: sizes, scale: s, anchor: anchor, area: area, gap: gap)
    }

    public static let miniatureWidth: CGFloat = 200
    public static let miniatureGap: CGFloat = 10
    /// How far beyond the screen edge a sliding miniature starts and ends.
    public static let offscreenDistance: CGFloat = 30

    /// Layout "Miniatur": one column at `side`, starting at the top of the visible area minus
    /// `margin`, `gap` apart. Every entry is `miniWidth` wide with the aspect of its full size,
    /// except `expandedIndex`, which has its full size (fitted into the visible area minus the
    /// margins, aspect kept) and stays anchored at the top outer corner. Entries that do not fit
    /// run off below `visible.minY`: nothing shrinks and there is no second column.
    /// An expanded entry that would run below the area moves up instead (`liftExpanded`).
    public static func miniatureFrames(
        fullSizes: [CGSize],
        expandedIndex: Int?,
        side: PopupAnchor.Horizontal,
        visible: CGRect,
        margin: CGFloat,
        miniWidth: CGFloat = PopupStackLayout.miniatureWidth,
        gap: CGFloat = PopupStackLayout.miniatureGap
    ) -> [CGRect] {
        let area = miniatureArea(visible: visible, margin: margin)
        var top = area.maxY
        let frames = fullSizes.enumerated().map { index, full in
            let size = miniatureSize(full: full, expanded: index == expandedIndex, area: area, miniWidth: miniWidth)
            let frame = miniatureFrame(size: size, top: top, side: side, area: area)
            top -= size.height + gap
            return frame
        }
        guard let expandedIndex else { return frames }
        return liftExpanded(frames, expandedIndex: expandedIndex, side: side, area: area, gap: gap)
    }

    /// The expanded entry would run below `area`: it moves up until its bottom is at `area.minY`,
    /// at most to the top of the area, without covering a miniature. Entries before it that fit
    /// completely above its new top keep their frames; the other ones before it follow directly
    /// below it in their order, then the ones after it (they may run off below the screen). The
    /// order of the entries does not change: once it is small again, the column is as before.
    static func liftExpanded(
        _ frames: [CGRect],
        expandedIndex: Int,
        side: PopupAnchor.Horizontal,
        area: CGRect,
        gap: CGFloat
    ) -> [CGRect] {
        guard frames.indices.contains(expandedIndex) else { return frames }
        let big = frames[expandedIndex]
        guard big.minY < area.minY else { return frames }
        let top = max(big.maxY, min(area.maxY, area.minY + big.height))
        var result = frames
        result[expandedIndex] = miniatureFrame(size: big.size, top: top, side: side, area: area)
        let displacedBefore = frames.indices.prefix(expandedIndex).filter { frames[$0].minY < top + gap }
        let below = displacedBefore + Array(frames.indices.suffix(from: expandedIndex + 1))
        var cursor = result[expandedIndex].minY - gap
        for i in below {
            result[i] = miniatureFrame(size: frames[i].size, top: cursor, side: side, area: area)
            cursor -= frames[i].height + gap
        }
        return result
    }

    /// The visible area minus the margin on every side (the miniature column's bounds).
    public static func miniatureArea(visible: CGRect, margin: CGFloat) -> CGRect {
        visible.insetBy(dx: min(margin, visible.width / 2), dy: min(margin, visible.height / 2))
    }

    /// Size of one entry in the miniature column: `miniWidth` wide with the aspect of `full`, or
    /// (`expanded`) its full size fitted into `area` with the aspect kept.
    public static func miniatureSize(
        full: CGSize,
        expanded: Bool,
        area: CGRect,
        miniWidth: CGFloat = PopupStackLayout.miniatureWidth
    ) -> CGSize {
        let full = CGSize(width: max(full.width, 1), height: max(full.height, 1))
        if expanded {
            let s = min(1, area.width / full.width, area.height / full.height)
            return CGSize(width: (full.width * s).rounded(.down), height: (full.height * s).rounded(.down))
        }
        return CGSize(width: miniWidth, height: (miniWidth * full.height / full.width).rounded())
    }

    /// `size` hanging from `top` at the outer edge (`side`) of `area`.
    public static func miniatureFrame(size: CGSize, top: CGFloat, side: PopupAnchor.Horizontal, area: CGRect) -> CGRect {
        let x: CGFloat
        switch side {
        case .leading: x = area.minX
        case .trailing: x = area.maxX - size.width
        case .center: x = (area.midX - size.width / 2).rounded()
        }
        return CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }

    /// `frame` moved horizontally completely beyond the outer edge of `screenFrame`
    /// (+ `offscreenDistance`): start of the slide-in and end of the slide-out.
    public static func offscreenFrame(
        for frame: CGRect,
        side: PopupAnchor.Horizontal,
        screenFrame: CGRect
    ) -> CGRect {
        var result = frame
        switch side {
        case .leading: result.origin.x = screenFrame.minX - frame.width - offscreenDistance
        case .trailing, .center: result.origin.x = screenFrame.maxX + offscreenDistance
        }
        return result
    }

    /// Start of the slide-in and end of the slide-out of a miniature at `frame`: beyond the outer
    /// edge (`offscreenFrame`) as long as no other screen lies there. Next to a neighbouring screen
    /// the popup would show on it while sliding: it stays on its own screen instead, touching the
    /// outer edge, and fades (`fades`: alpha 0 at this end).
    public static func slideEnd(
        for frame: CGRect,
        side: PopupAnchor.Horizontal,
        screenFrame: CGRect,
        otherScreens: [CGRect]
    ) -> MiniatureSlideEnd {
        let outside = offscreenFrame(for: frame, side: side, screenFrame: screenFrame)
        let path: CGRect
        var inside = frame
        switch side {
        case .leading:
            path = CGRect(x: outside.minX, y: frame.minY, width: screenFrame.minX - outside.minX, height: frame.height)
            inside.origin.x = screenFrame.minX
        case .trailing, .center:
            path = CGRect(x: screenFrame.maxX, y: frame.minY, width: outside.maxX - screenFrame.maxX, height: frame.height)
            inside.origin.x = screenFrame.maxX - frame.width
        }
        let crossesNeighbour = otherScreens.contains { screen in
            let overlap = screen.intersection(path)
            return !overlap.isNull && overlap.width > 0 && overlap.height > 0
        }
        return crossesNeighbour
            ? MiniatureSlideEnd(frame: inside, fades: true)
            : MiniatureSlideEnd(frame: outside, fades: false)
    }

    /// Consecutive groups: the first `ceil(n / count)` popups in column 1, and so on.
    static func split(_ indices: [Int], into count: Int) -> [[Int]] {
        let perColumn = Int((Double(indices.count) / Double(count)).rounded(.up))
        return stride(from: 0, to: indices.count, by: perColumn).map {
            Array(indices[$0..<min($0 + perColumn, indices.count)])
        }
    }

    static func scale(columns: [[Int]], sizes: [CGSize], area: CGSize, gap: CGFloat) -> CGFloat {
        var s: CGFloat = 1
        for column in columns {
            let heights = column.reduce(0) { $0 + sizes[$1].height }
            let room = area.height - gap * CGFloat(column.count - 1)
            s = min(s, room / heights)
        }
        let widths = columns.reduce(0) { total, column in total + (column.map { sizes[$0].width }.max() ?? 0) }
        s = min(s, (area.width - gap * CGFloat(columns.count - 1)) / widths)
        return max(s, 0.01)
    }

    private static func place(
        columns: [[Int]],
        sizes: [CGSize],
        scale s: CGFloat,
        anchor: PopupAnchor,
        area: CGRect,
        gap: CGFloat
    ) -> [CGRect] {
        let scaled = sizes.map { CGSize(width: ($0.width * s).rounded(.down), height: ($0.height * s).rounded(.down)) }
        let columnWidths = columns.map { column in column.map { scaled[$0].width }.max() ?? 0 }
        let totalWidth = columnWidths.reduce(0, +) + gap * CGFloat(columns.count - 1)
        var frames = [CGRect](repeating: .zero, count: sizes.count)

        // Column 1 sits at the anchor; further columns grow away from it (centered: as one block).
        var cursor: CGFloat
        switch anchor.horizontal {
        case .leading: cursor = area.minX
        case .trailing: cursor = area.maxX
        case .center: cursor = (area.midX - totalWidth / 2).rounded()
        }
        for (index, column) in columns.enumerated() {
            let width = columnWidths[index]
            let columnMinX: CGFloat
            switch anchor.horizontal {
            case .leading, .center:
                columnMinX = cursor
                cursor += width + gap
            case .trailing:
                columnMinX = cursor - width
                cursor -= width + gap
            }
            let columnHeight = column.reduce(0) { $0 + scaled[$1].height } + gap * CGFloat(column.count - 1)
            var top: CGFloat
            switch anchor.vertical {
            case .top: top = area.maxY
            case .middle: top = (area.midY + columnHeight / 2).rounded()
            case .bottom: top = area.minY + columnHeight
            }
            // Bottom anchors keep the first popup at the bottom edge (stack grows upward).
            let ordered = anchor.vertical == .bottom ? column.reversed() : column
            for item in ordered {
                let size = scaled[item]
                let x: CGFloat
                switch anchor.horizontal {
                case .leading: x = columnMinX
                case .trailing: x = columnMinX + width - size.width
                case .center: x = (columnMinX + (width - size.width) / 2).rounded()
                }
                frames[item] = CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
                top -= size.height + gap
            }
        }
        return frames
    }
}

/// The popup's bottom pill (padding 6, gap 8, circles 34) must stay 10 pt inside the popup, or the
/// window would grow with it. The two-line talk button is used while it fits, else only the microphone.
public enum PopupPillFit {
    public static func talkButtonFits(popupWidth: CGFloat, circles: Int, talkWidth: CGFloat) -> Bool {
        12 + CGFloat(max(circles, 0)) * (34 + 8) + talkWidth <= popupWidth - 20
    }
}
