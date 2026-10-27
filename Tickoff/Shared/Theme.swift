import AppKit
import SwiftUI

/// Look and feel: the user-selectable appearance preferences and how they map onto SwiftUI.
/// Features read these through `Appearance` (and `View.applying(_:)`) instead of hard-coding colours.

enum ThemeMode: String, CaseIterable, Sendable {
    case light, dark, system

    var label: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "System"
        }
    }

    /// The value stored under `theme_mode`.
    var key: String { rawValue }

    init?(key: String) { self.init(rawValue: key) }

    /// `nil` follows the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

enum Accent: String, CaseIterable, Sendable {
    case system, indigo, violet, teal, rose, orange

    var label: String {
        switch self {
        case .system: "System"
        case .indigo: "Indigo"
        case .violet: "Violet"
        case .teal: "Teal"
        case .rose: "Rose"
        case .orange: "Orange"
        }
    }

    /// The value stored under `accent`.
    var key: String { rawValue }

    init?(key: String) { self.init(rawValue: key) }

    /// Bright variants on dark backgrounds, deeper variants on light ones (the Rust app's values).
    /// `nil` for `.system`, which uses the colour chosen in System Settings.
    func hex(dark: Bool) -> UInt32? {
        switch (self, dark) {
        case (.system, _): nil
        case (.indigo, true): 0x7C83FF
        case (.indigo, false): 0x5058E6
        case (.violet, true): 0xA78BFA
        case (.violet, false): 0x7C3AED
        case (.teal, true): 0x2DD4BF
        case (.teal, false): 0x0D9488
        case (.rose, true): 0xFB7185
        case (.rose, false): 0xE11D48
        case (.orange, true): 0xFB923C
        case (.orange, false): 0xEA580C
        }
    }

    /// Resolves against the window's effective appearance, so it follows light/dark live;
    /// `.system` follows the macOS accent colour live too.
    var color: Color {
        guard self != .system else { return Color(nsColor: .controlAccentColor) }
        return Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor(srgbHex: self.hex(dark: isDark) ?? 0)
            })
    }
}

enum UiScale: String, CaseIterable, Sendable {
    case small
    case standard = "default"
    case large

    var label: String {
        switch self {
        case .small: "Small"
        case .standard: "Default"
        case .large: "Large"
        }
    }

    /// The value stored under `ui_scale`.
    var key: String { rawValue }

    init?(key: String) { self.init(rawValue: key) }

    /// The Rust app's zoom factors. macOS ignores Dynamic Type, so text is scaled explicitly.
    var factor: CGFloat {
        switch self {
        case .small: 0.9
        case .standard: 1.0
        case .large: 1.15
        }
    }

    /// The default font for views that don't set their own, at this scale.
    var bodyFont: Font { .system(size: NSFont.systemFontSize * factor) }
}

struct Appearance: Equatable, Sendable {
    var mode: ThemeMode = .system
    var accent: Accent = .system
    var scale: UiScale = .standard
    var compactCards = false
    var showNotes = true

    static let `default` = Appearance()
}

extension Appearance {
    /// A font `relativeSize` times the macOS body size at the chosen text size. Features use this
    /// for headings and captions so they follow the text-size setting like the body text does.
    func font(_ relativeSize: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
        .system(size: NSFont.systemFontSize * scale.factor * relativeSize, weight: weight)
    }
}

extension View {
    /// Applies the colour scheme, accent and text size, live, to everything inside this view.
    func applying(_ appearance: Appearance) -> some View {
        preferredColorScheme(appearance.mode.colorScheme)
            .tint(appearance.accent.color)
            .font(appearance.scale.bodyFont)
    }
}

extension NSColor {
    fileprivate convenience init(srgbHex hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    }
}
