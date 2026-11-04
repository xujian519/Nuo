//
//  ThemeSystemAccentTests.swift
//  OsaurusCoreTests
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite("System accent following")
struct ThemeSystemAccentTests {
    /// Schema 7 起，强调色是品牌色（朱红），任何内建主题都不跟随系统强调色。
    /// 跟随能力保留给用户自定义主题。
    @Test("no built-in theme follows the system accent")
    func builtInPresetsOptOut() {
        for theme in CustomTheme.allBuiltInPresets {
            #expect(!theme.followsSystemAccent, "\(theme.metadata.name) 不应跟随系统强调色")
        }
    }

    @Test("decoding JSON without the flag defaults to false; round-trip preserves true")
    func decodingDefaultsAndRoundTrips() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Round-trip preserves the flag (opt in explicitly — built-ins are opt-out).
        var following = CustomTheme.darkDefault
        following.followsSystemAccent = true
        let encoded = try encoder.encode(following)
        let roundTripped = try decoder.decode(CustomTheme.self, from: encoded)
        #expect(roundTripped.followsSystemAccent)

        // A legacy payload without the key decodes to false.
        var json = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        json.removeValue(forKey: "followsSystemAccent")
        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let legacy = try decoder.decode(CustomTheme.self, from: legacyData)
        #expect(!legacy.followsSystemAccent)
    }

    @Test("applying the stored accent is an identity")
    func identityWhenAccentMatchesStoredValue() {
        let dark = CustomTheme.darkDefault.colors
        #expect(dark.applyingAccent(dark.accentColor, isDark: true) == dark)
        // Case and prefix insensitive.
        #expect(dark.applyingAccent(dark.accentColor.uppercased(), isDark: true) == dark)
        #expect(dark.applyingAccent(String(dark.accentColor.dropFirst()), isDark: true) == dark)

        let light = CustomTheme.lightDefault.colors
        #expect(light.applyingAccent(light.accentColor, isDark: false) == light)
    }

    @Test("invalid accent input leaves colors unchanged")
    func invalidAccentIsIgnored() {
        let colors = CustomTheme.darkDefault.colors
        #expect(colors.applyingAccent("not-a-color", isDark: true) == colors)
        #expect(colors.applyingAccent("#fff", isDark: true) == colors)
    }

    @Test("a new accent rewrites only the accent-adjacent fields")
    func derivationRewritesAccentAdjacentFieldsOnly() {
        let purple = "#a550a7"
        let base = CustomTheme.darkDefault.colors
        let derived = base.applyingAccent(purple, isDark: true)

        #expect(derived.accentColor == purple)
        #expect(derived.focusBorder == purple)
        #expect(derived.cursorColor == purple)
        #expect(derived.selectionColor == purple + "45")
        #expect(derived.accentColorLight != base.accentColorLight)
        #expect(derived.sidebarSelectedBackground != base.sidebarSelectedBackground)
        #expect(derived.infoColor == derived.accentColorLight)

        // Everything else stays authored.
        #expect(derived.primaryText == base.primaryText)
        #expect(derived.secondaryText == base.secondaryText)
        #expect(derived.primaryBackground == base.primaryBackground)
        #expect(derived.secondaryBackground == base.secondaryBackground)
        #expect(derived.sidebarBackground == base.sidebarBackground)
        #expect(derived.successColor == base.successColor)
        #expect(derived.warningColor == base.warningColor)
        #expect(derived.errorColor == base.errorColor)
        #expect(derived.cardBackground == base.cardBackground)
        #expect(derived.buttonBackground == base.buttonBackground)
        #expect(derived.inputBackground == base.inputBackground)
        #expect(derived.shadowColor == base.shadowColor)
        #expect(derived.placeholderText == base.placeholderText)
    }

    @Test("light derivation uses the light selection alpha and accent info color")
    func lightDerivationUsesLightRules() {
        let purple = "#a550a7"
        let base = CustomTheme.lightDefault.colors
        let derived = base.applyingAccent(purple, isDark: false)

        #expect(derived.selectionColor == purple + "26")
        #expect(derived.infoColor == purple)
        // Light selected-row color blends toward white, so it should be
        // much lighter than the accent itself.
        #expect(derived.sidebarSelectedBackground != base.sidebarSelectedBackground)
        #expect(derived.sidebarSelectedBackground.hasPrefix("#"))
    }
}
