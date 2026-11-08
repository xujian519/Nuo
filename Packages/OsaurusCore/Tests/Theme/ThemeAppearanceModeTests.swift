//
//  ThemeAppearanceModeTests.swift
//  osaurusTests
//

import Foundation
import Testing

@testable import OsaurusCore

@MainActor
struct ThemeAppearanceModeTests {
    /// 内建目录只有浅色与深色两个。
    ///
    /// 它们同时是"跟随系统"的外观锚点：`AppearanceMode.system` 会在这两个
    /// 之间切换。其它配色一律走导入 / 复制自改，不再作为内建预设存在。
    @Test
    func builtInCatalogIsLightAndDarkOnly() {
        let presets = CustomTheme.allBuiltInPresets
        #expect(presets.count == 2)
        #expect(presets.map(\.metadata.name) == ["Dark", "Light"])
        #expect(Set(presets.map(\.metadata.id)).count == presets.count)
    }

    /// 已下线的内建预设不得再出现在目录里。
    ///
    /// 这些 id 曾经是 Neon / Nord / Paper / Terminal / Nuo Dark / Nuo Light。
    /// 它们留在目录里的后果不是"多了几个选项"，而是存量安装里残留的
    /// 旧 JSON 仍会被当成主题读出来。
    @Test
    func retiredPresetsAreGone() {
        let retired = [
            "00000000-0000-0000-0000-000000000003",
            "00000000-0000-0000-0000-000000000004",
            "00000000-0000-0000-0000-000000000005",
            "00000000-0000-0000-0000-000000000006",
            "00000000-0000-0000-0000-000000000007",
            "00000000-0000-0000-0000-000000000008",
        ].compactMap(UUID.init(uuidString:))

        #expect(retired.count == 6)
        let ids = Set(CustomTheme.allBuiltInPresets.map(\.metadata.id))
        for id in retired {
            #expect(!ids.contains(id), "已下线的内建预设 \(id) 不应再出现在目录里")
        }
    }

    @Test
    func appearanceModeOnlyMapsCanonicalLightAndDarkBuiltIns() {
        #expect(ThemeManager.appearanceMode(forBuiltInTheme: CustomTheme.darkDefault) == .dark)
        #expect(ThemeManager.appearanceMode(forBuiltInTheme: CustomTheme.lightDefault) == .light)
        // 每个内建主题都必须能映射到外观模式，否则"跟随系统"无法工作。
        for theme in CustomTheme.allBuiltInPresets {
            #expect(ThemeManager.appearanceMode(forBuiltInTheme: theme) != nil)
        }
    }

    /// Schema 8：默认皮肤是 Nuo 的「纸与印」，色值全部来自 `NuoHex`
    /// （Radix Colors 12 级色阶）。这条测试钉住字面值——色板换了必须
    /// 显式改这里，而不是让对比度悄悄漂移。
    @Test
    func canonicalDefaultsUseNuoPalette() {
        let dark = CustomTheme.darkDefault
        #expect(dark.metadata.name == "Dark")
        #expect(dark.colors.primaryBackground == "#191918")
        #expect(dark.colors.primaryText == "#EEEEEC")
        #expect(dark.colors.accentColor == "#EC6142")
        // 三级文字带 alpha（sand-12 @ 65%），见 NuoThemeSkin。
        #expect(dark.colors.tertiaryText == "#EEEEECA6")
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
        #expect(light.colors.primaryBackground == "#F9F9F8")
        #expect(light.colors.primaryText == "#21201C")
        #expect(light.colors.accentColor == "#D13415")
        #expect(light.colors.tertiaryText == "#21201CA6")
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

    /// 已下线的内建预设不得在启动时生效。
    ///
    /// 内建预设的文件是在 schema 递增时删掉的，而活动主题在
    /// `ThemeManager.init` 里读得比那更早——启动时还认它，App 就会带着
    /// 一个已经被移出目录的配色跑完整个会话。
    @Test
    func startupSelectionTreatsRetiredBuiltInsAsAbsent() {
        var retired = CustomTheme.darkDefault
        retired.metadata.id = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        retired.metadata.name = "Neon"
        retired.isBuiltIn = true

        let selection = ThemeManager.startupSelection(
            savedActiveTheme: retired,
            configuredAppearanceMode: .system
        )
        #expect(selection.appearanceMode == .system)
        #expect(selection.activeTheme == nil)
        #expect(selection.shouldClearActiveTheme)
    }

    /// 用户自己的主题仍然按用户选择保留，不被外观模式改写。
    ///
    /// 这一条在删掉非规范内建预设之后更重要：以前可以用"某个非规范内建
    /// 预设"当样本，现在唯一的样本就是自定义主题。
    @Test
    func startupSelectionPreservesCustomThemes() {
        var custom = CustomTheme.darkDefault
        custom.metadata.id = UUID()
        custom.metadata.name = "My Theme"
        custom.isBuiltIn = false

        let selection = ThemeManager.startupSelection(
            savedActiveTheme: custom,
            configuredAppearanceMode: .system
        )
        #expect(selection.appearanceMode == .system)
        #expect(selection.activeTheme?.metadata.id == custom.metadata.id)
        #expect(!selection.shouldClearActiveTheme)

        let emptySelection = ThemeManager.startupSelection(
            savedActiveTheme: nil,
            configuredAppearanceMode: .dark
        )
        #expect(emptySelection.appearanceMode == .dark)
        #expect(emptySelection.activeTheme == nil)
        #expect(!emptySelection.shouldClearActiveTheme)
    }
}
