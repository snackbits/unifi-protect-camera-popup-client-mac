import AppKit
import SwiftUI

/// sRGB color with alpha as written in the template (`#RRGGBB`, `rgba(r,g,b,a)`).
public struct RGBA: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public let alpha: Double

    public init(_ hex: UInt32, alpha: Double = 1) {
        red = UInt8((hex >> 16) & 0xFF)
        green = UInt8((hex >> 8) & 0xFF)
        blue = UInt8(hex & 0xFF)
        self.alpha = alpha
    }

    public var nsColor: NSColor {
        NSColor(
            srgbRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha)
        )
    }
}

/// A template token with its light ("Hell") and dark ("Dunkel") value.
public struct ThemeColor: Equatable, Sendable {
    public let light: RGBA
    public let dark: RGBA

    public init(light: RGBA, dark: RGBA) {
        self.light = light
        self.dark = dark
    }

    public init(_ light: UInt32, _ dark: UInt32) {
        self.init(light: RGBA(light), dark: RGBA(dark))
    }

    public static func fixed(_ value: RGBA) -> ThemeColor {
        ThemeColor(light: value, dark: value)
    }

    /// Resolves at draw time against the current appearance (window, popup or `NSApp.appearance`).
    public var nsColor: NSColor {
        let light = light
        let dark = dark
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark.nsColor : light.nsColor
        }
    }

    public var color: Color {
        Color(nsColor: nsColor)
    }
}

/// Tokens of the template's `light` / `night` objects. Names and values: docs/design/tokens.md.
public enum Tokens {
    // Einstellungen.dc.html
    public static let page = ThemeColor(0xDCDDE6, 0x121318)
    public static let win = ThemeColor(0xFBFBFD, 0x26262C)
    public static let bar = ThemeColor(0xF3F3F7, 0x2C2C33)
    public static let side = ThemeColor(0xF2F2F6, 0x222227)
    public static let group = ThemeColor(0xFFFFFF, 0x2E2E35)
    public static let fg = ThemeColor(0x1D1D1F, 0xEDEDF2)
    public static let muted = ThemeColor(0x55555F, 0xABABB7)
    public static let accent = ThemeColor(0x4B3FD1, 0x5B4FE0)
    public static let accSoft = ThemeColor(0xECEAFB, 0x312C5C)
    public static let accText = ThemeColor(0x3528A8, 0xC3BDFF)
    public static let border = ThemeColor(0xDEDEE6, 0x3B3B45)
    public static let field = ThemeColor(0xFFFFFF, 0x1C1C21)
    public static let ok = ThemeColor(0x1C6B30, 0x86E3A6)
    public static let okBg = ThemeColor(0xE3F5E8, 0x1F3A2A)
    public static let segBg = ThemeColor(0xE8E8EE, 0x1C1C21)
    public static let segOn = ThemeColor(0xFFFFFF, 0x3E3E48)
    public static let segShadow = ThemeColor(light: RGBA(0x000000, alpha: 0.14), dark: RGBA(0x000000, alpha: 0.4))
    public static let chipOff = ThemeColor(0xFFFFFF, 0x34343C)
    public static let chipBorder = ThemeColor(0xC9C9D6, 0x4A4A55)
    public static let naFg = ThemeColor(0x7A7A86, 0x8A8A97)
    public static let toggleOff = ThemeColor(0xD1D1D8, 0x4A4A55)
    public static let btn2 = ThemeColor(0xEFEFF4, 0x34343C)
    public static let scrim = ThemeColor(light: RGBA(0x1E1E32, alpha: 0.18), dark: RGBA(0x000000, alpha: 0.42))
    public static let tabOn = ThemeColor(0xE4E2F8, 0x3A3566)

    // Main.dc.html (onboarding, menu panel, popup), where it differs from the settings
    public static let mainBorder = ThemeColor(0xD9D9E3, 0x3B3B45)
    public static let mainChipOff = ThemeColor(0xFFFFFF, 0x2E2E35)
    public static let menu = ThemeColor(0xFBFBFD, 0x2B2B31)
    public static let dotOff = ThemeColor(0xC9C9D6, 0x4A4A55)
    public static let dropBorder = ThemeColor(0xB8B2F2, 0x6D63D9)
    public static let pill = ThemeColor(light: RGBA(0xFAFAFC, alpha: 0.9), dark: RGBA(0x141518, alpha: 0.84))
    public static let pillRing = ThemeColor(light: RGBA(0x000000, alpha: 0.08), dark: RGBA(0xFFFFFF, alpha: 0.1))
    public static let pillBtn = ThemeColor(0xE6E6EE, 0x3A3B42)
    public static let pillFg = ThemeColor(0x1D1D1F, 0xEDEDF0)

    // Same in both appearances
    public static let overlay = ThemeColor.fixed(RGBA(0x000000, alpha: 0.62))
    public static let white = ThemeColor.fixed(RGBA(0xFFFFFF))
    public static let statusGreen = ThemeColor.fixed(RGBA(0x34C759))
    public static let stripeA = ThemeColor.fixed(RGBA(0x2A2D36))
    public static let stripeB = ThemeColor.fixed(RGBA(0x30343E))
    public static let popupRing = ThemeColor.fixed(RGBA(0xFFFFFF, alpha: 0.1))
}
