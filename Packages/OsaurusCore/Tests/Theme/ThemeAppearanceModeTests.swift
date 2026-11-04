//
//  ThemeAppearanceModeTests.swift
//  osaurusTests
//

import Testing

@testable import OsaurusCore

@MainActor
struct ThemeAppearanceModeTests {
    @Test
    func appearanceModeOnlyMapsCanonicalLightAndDarkBuiltIns() {
        #expect(ThemeManager.appearanceMode(forBuiltInTheme: CustomTheme.darkDefault) == .dark)
        #expect(ThemeManager.appearanceMode(forBuiltInTheme: CustomTheme.lightDefault) == .light)
        #expect(ThemeManager.appearanceMode(forBuiltInTheme: CustomTheme.neonPreset) == nil)
        #expect(ThemeManager.appearanceMode(forBuiltInTheme: CustomTheme.nordPreset) == nil)
        #expect(ThemeManager.appearanceMode(forBuiltInTheme: CustomTheme.paperPreset) == nil)
        #expect(ThemeManager.appearanceMode(forBuiltInTheme: CustomTheme.terminalPreset) == nil)
        #expect(ThemeManager.appearanceMode(forBuiltInTheme: CustomTheme.osaurusDarkPreset) == nil)
        #expect(ThemeManager.appearanceMode(forBuiltInTheme: CustomTheme.osaurusLightPreset) == nil)
    }

    @Test
    func builtInPresetIdsAreUnique() {
        let ids = CustomTheme.allBuiltInPresets.map(\.metadata.id)
        #expect(Set(ids).count == ids.count)
        #expect(CustomTheme.allBuiltInPresets.contains { $0.metadata.id == CustomTheme.osaurusDarkPreset.metadata.id })
        #expect(CustomTheme.allBuiltInPresets.contains { $0.metadata.id == CustomTheme.osaurusLightPreset.metadata.id })
    }

    /// Schema 7：默认皮肤是 Nuo 的「纸与印」，色值全部来自 `NuoHex`。
    /// 这条测试同时钉住两件事：底色/强调色的字面值，以及"强调色不跟随系统"。
    @Test
    func canonicalDefaultsUseNuoPalette() {
        let dark = CustomTheme.darkDefault
        #expect(dark.metadata.name == "Dark")
        #expect(dark.colors.primaryBackground == "#161512")
        #expect(dark.colors.primaryText == "#F2EEE4")
        #expect(dark.colors.accentColor == "#EB5B45")
        #expect(!dark.followsSystemAccent)
        // 阶段 1.5：纸是平的。三个玻璃开关必须同时关——
        // 只关 enabled 会留下侧栏/输入卡两块毛玻璃。
        #expect(!dark.glass.enabled)
        #expect(!dark.glass.sidebarEnabled)
        #expect(!dark.glass.inputEnabled)
        #expect(dark.glass.material == .windowBackground)
        #expect(dark.isDark)

        let light = CustomTheme.lightDefault
        #expect(light.metadata.name == "Light")
        #expect(light.colors.primaryBackground == "#F7F4ED")
        #expect(light.colors.primaryText == "#1C1A17")
        #expect(light.colors.accentColor == "#C93A2B")
        #expect(!light.followsSystemAccent)
        #expect(!light.glass.enabled)
        #expect(!light.glass.sidebarEnabled)
        #expect(!light.glass.inputEnabled)
        #expect(light.glass.material == .windowBackground)
        #expect(!light.isDark)
    }

    /// 朱红是品牌语义，不能被系统强调色替换；所有内建主题都不自动跟随。
    /// 跟随能力仍然保留给用户自定义主题（`applyingAccent` 的测试覆盖了推导本身）。
    @Test
    func builtInThemesDoNotFollowSystemAccent() {
        for theme in CustomTheme.allBuiltInPresets {
            #expect(
                !theme.followsSystemAccent,
                "\(theme.metadata.name) 不应跟随系统强调色"
            )
        }
    }

    @Test
    func osaurusPresetsRetainLegacyDefaultPalettes() {
        let dark = CustomTheme.osaurusDarkPreset
        #expect(dark.metadata.name == "Nuo Dark")
        #expect(dark.isBuiltIn)
        #expect(dark.isDark)
        #expect(dark.colors.primaryBackground == "#0e1120")
        #expect(dark.colors.accentColor == "#4a6de0")
        #expect(!dark.glass.enabled)

        let light = CustomTheme.osaurusLightPreset
        #expect(light.metadata.name == "Nuo Light")
        #expect(light.isBuiltIn)
        #expect(!light.isDark)
        #expect(light.colors.primaryBackground == "#ffffea")
        #expect(light.colors.accentColor == "#214099")
        #expect(!light.glass.enabled)
    }

    @Test
    func startupSelectionNormalizesCanonicalBuiltInActiveThemes() {
        let lightSelection = ThemeManager.startupSelection(
            savedActiveTheme: CustomTheme.lightDefault,
            configuredAppearanceMode: .system
        )
        #expect(lightSelection.appearanceMode == .light)
        #expect(lightSelection.activeTheme == nil)
        #expect(lightSelection.shouldClearActiveTheme)

        let darkSelection = ThemeManager.startupSelection(
            savedActiveTheme: CustomTheme.darkDefault,
            configuredAppearanceMode: .light
        )
        #expect(darkSelection.appearanceMode == .dark)
        #expect(darkSelection.activeTheme == nil)
        #expect(darkSelection.shouldClearActiveTheme)
    }

    @Test
    func startupSelectionPreservesCustomAndNonCanonicalBuiltIns() {
        let neonSelection = ThemeManager.startupSelection(
            savedActiveTheme: CustomTheme.neonPreset,
            configuredAppearanceMode: .system
        )
        #expect(neonSelection.appearanceMode == .system)
        #expect(neonSelection.activeTheme?.metadata.id == CustomTheme.neonPreset.metadata.id)
        #expect(!neonSelection.shouldClearActiveTheme)

        let osaurusDarkSelection = ThemeManager.startupSelection(
            savedActiveTheme: CustomTheme.osaurusDarkPreset,
            configuredAppearanceMode: .system
        )
        #expect(osaurusDarkSelection.appearanceMode == .system)
        #expect(osaurusDarkSelection.activeTheme?.metadata.id == CustomTheme.osaurusDarkPreset.metadata.id)
        #expect(!osaurusDarkSelection.shouldClearActiveTheme)

        let emptySelection = ThemeManager.startupSelection(
            savedActiveTheme: nil,
            configuredAppearanceMode: .dark
        )
        #expect(emptySelection.appearanceMode == .dark)
        #expect(emptySelection.activeTheme == nil)
        #expect(!emptySelection.shouldClearActiveTheme)
    }
}
