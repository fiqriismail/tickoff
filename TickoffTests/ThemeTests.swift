import SwiftUI
import Testing

@testable import Tickoff

struct ThemeTests {
    @Test func keysRoundTripForEveryOption() {
        for mode in ThemeMode.allCases { #expect(ThemeMode(key: mode.key) == mode) }
        for accent in Accent.allCases { #expect(Accent(key: accent.key) == accent) }
        #expect(ThemeMode(key: "nonsense") == nil)
        #expect(Accent(key: "nonsense") == nil)
    }

    @Test func keysAreTheStringsTheRustAppStored() {
        #expect(ThemeMode.allCases.map(\.key) == ["light", "dark", "system"])
        #expect(Accent.allCases.map(\.key) == ["system", "indigo", "violet", "teal", "rose", "orange"])
    }

    @Test func labelsAreTheUserFacingNames() {
        #expect(ThemeMode.allCases.map(\.label) == ["Light", "Dark", "System"])
        #expect(Accent.allCases.map(\.label) == ["System", "Indigo", "Violet", "Teal", "Rose", "Orange"])
    }

    @Test func themeModeMapsToAColorSchemeAndSystemFollowsTheOS() {
        #expect(ThemeMode.light.colorScheme == .light)
        #expect(ThemeMode.dark.colorScheme == .dark)
        #expect(ThemeMode.system.colorScheme == nil)
    }

    @Test func accentColoursKeepTheRustLightAndDarkValues() {
        #expect(Accent.indigo.hex(dark: true) == 0x7C83FF)
        #expect(Accent.indigo.hex(dark: false) == 0x5058E6)
        #expect(Accent.violet.hex(dark: true) == 0xA78BFA)
        #expect(Accent.violet.hex(dark: false) == 0x7C3AED)
        #expect(Accent.teal.hex(dark: true) == 0x2DD4BF)
        #expect(Accent.teal.hex(dark: false) == 0x0D9488)
        #expect(Accent.rose.hex(dark: true) == 0xFB7185)
        #expect(Accent.rose.hex(dark: false) == 0xE11D48)
        #expect(Accent.orange.hex(dark: true) == 0xFB923C)
        #expect(Accent.orange.hex(dark: false) == 0xEA580C)
    }

    @Test func theSystemAccentHasNoFixedColourSoItFollowsMacOS() {
        #expect(Accent.system.hex(dark: true) == nil)
        #expect(Accent.system.hex(dark: false) == nil)
    }
}
