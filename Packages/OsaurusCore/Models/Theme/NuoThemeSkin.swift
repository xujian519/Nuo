//
//  NuoThemeSkin.swift
//  osaurus
//
//  「纸与印」配色的唯一真源。
//
//  为什么单独一个文件而不直接写在 CustomTheme 的两个默认预设里：
//  `ThemeColors` 有 29 个字段，两个预设各写一遍就是 58 行几乎重复的十六进制，
//  改一个色要改两处，而且很容易只改一处。这里把"哪个语义对应哪个色阶"
//  集中表达一次，两个方向只差一个纸/夜纸的取值。
//
//  所有色值都经由 `NuoHex`（设计令牌包）取出，**不在这里写裸十六进制**。
//  这样设计系统与产品永远用同一套色：改 NuoHex，App 与原型一起变。
//  唯一的例外是 alpha 后缀（selectionColor / glassTintOverlay），因为令牌层
//  只描述纯色。
//
//  三条映射纪律（与 DESIGN_SPEC.md §3.1 对应）：
//  1. 朱红只映射到 accent / focus / cursor / selection / sidebarSelected 这五个
//     "承诺与存在"面，不映射到 info / success / warning / error。
//  2. `buttonBackground` 是**中性面**（仓库里 11 处都拿它当图标按钮的底），
//     绝不能填墨色，否则所有次级按钮会变成黑块。
//  3. `infoColor` 不引入蓝色——这套系统只有纸与朱两个色相，
//     信息态用二级墨色表达，靠图标而不是色相区分。
//
//  ⚠️ 实参顺序必须与 `ThemeColors.init` 的声明顺序一致（Swift 的硬性要求）：
//  primaryText → secondaryText → tertiaryText → primaryBackground →
//  secondaryBackground → tertiaryBackground → sidebarBackground →
//  sidebarSelectedBackground → accentColor → accentColorLight → primaryBorder →
//  secondaryBorder → focusBorder → success → warning → error → info →
//  cardBackground → cardBorder → buttonBackground → buttonBorder →
//  inputBackground → inputBorder → glassTintOverlay → codeBlockBackground →
//  shadowColor → selectionColor → cursorColor → placeholderText
//

import Foundation
import NuoDesignSystem

enum NuoThemeSkin {

    // MARK: - 纸（浅色）

    /// 暖灰宣纸。用于 `CustomTheme.lightDefault`。
    static let paper = ThemeColors(
        primaryText: hex(NuoHex.ink.light),
        secondaryText: hex(NuoHex.inkSecondary.light),
        // 三级文字用 #6F6959（4.98:1）而不是更淡的墨——
        // 原 `LightTheme` 的三级色只有 2.8:1，时间戳在纸上几乎看不见。
        tertiaryText: hex(NuoHex.inkTertiary.light),

        primaryBackground: hex(NuoHex.paper.light),
        secondaryBackground: hex(NuoHex.paperRaised.light),
        tertiaryBackground: hex(NuoHex.paperSunken.light),

        sidebarBackground: hex(NuoHex.paperSunken.light),
        sidebarSelectedBackground: hex(NuoHex.cinnabarWash.light),

        accentColor: hex(NuoHex.cinnabar.light),
        accentColorLight: hex(NuoHex.cinnabarLight.light),

        primaryBorder: hex(NuoHex.hairline.light),
        secondaryBorder: hex(NuoHex.hairlineStrong.light),
        focusBorder: hex(NuoHex.cinnabar.light),

        successColor: hex(NuoHex.success.light),
        warningColor: hex(NuoHex.warning.light),
        errorColor: hex(NuoHex.danger.light),
        infoColor: hex(NuoHex.inkSecondary.light),

        cardBackground: hex(NuoHex.paperRaised.light),
        cardBorder: hex(NuoHex.hairline.light),
        // 比卡片亮一档：否则卡片上的图标按钮与卡片同色，在夜纸下直接隐形
        buttonBackground: hex(NuoHex.paperFloat.light),
        buttonBorder: hex(NuoHex.hairlineStrong.light),
        inputBackground: hex(NuoHex.paperFloat.light),
        inputBorder: hex(NuoHex.hairlineStrong.light),

        glassTintOverlay: hex(NuoHex.paperRaised.light) + "60",
        codeBlockBackground: hex(NuoHex.codeBackground.light),

        // 阴影用暖墨，不用纯黑——纯黑阴影落在暖纸上像脏污
        shadowColor: hex(NuoHex.ink.light),
        selectionColor: hex(NuoHex.cinnabar.light) + "40",
        cursorColor: hex(NuoHex.cinnabar.light),

        placeholderText: hex(NuoHex.inkTertiary.light)
    )

    // MARK: - 夜纸（深色）

    /// 夜纸。用于 `CustomTheme.darkDefault`。
    /// 不是"黑夜"，是把纸压到最暗还留着一点暖——所以底色是 #161512 而不是 #000。
    static let night = ThemeColors(
        primaryText: hex(NuoHex.ink.dark),
        secondaryText: hex(NuoHex.inkSecondary.dark),
        tertiaryText: hex(NuoHex.inkTertiary.dark),

        primaryBackground: hex(NuoHex.paper.dark),
        secondaryBackground: hex(NuoHex.paperRaised.dark),
        tertiaryBackground: hex(NuoHex.paperSunken.dark),

        sidebarBackground: hex(NuoHex.paperSunken.dark),
        sidebarSelectedBackground: hex(NuoHex.cinnabarWash.dark),

        accentColor: hex(NuoHex.cinnabar.dark),
        accentColorLight: hex(NuoHex.cinnabarLight.dark),

        primaryBorder: hex(NuoHex.hairline.dark),
        secondaryBorder: hex(NuoHex.hairlineStrong.dark),
        focusBorder: hex(NuoHex.cinnabar.dark),

        successColor: hex(NuoHex.success.dark),
        warningColor: hex(NuoHex.warning.dark),
        errorColor: hex(NuoHex.danger.dark),
        infoColor: hex(NuoHex.inkSecondary.dark),

        cardBackground: hex(NuoHex.paperRaised.dark),
        cardBorder: hex(NuoHex.hairline.dark),
        buttonBackground: hex(NuoHex.paperFloat.dark),
        buttonBorder: hex(NuoHex.hairlineStrong.dark),
        inputBackground: hex(NuoHex.paperFloat.dark),
        inputBorder: hex(NuoHex.hairlineStrong.dark),

        glassTintOverlay: "#00000030",
        codeBlockBackground: hex(NuoHex.codeBackground.dark),

        shadowColor: "#000000",
        selectionColor: hex(NuoHex.cinnabar.dark) + "60",
        cursorColor: hex(NuoHex.cinnabar.dark),

        placeholderText: hex(NuoHex.inkTertiary.dark)
    )

    // MARK: - 玻璃（阶段 1.5：关掉）

    /// 纸是平的。
    ///
    /// 关掉玻璃不是省 GPU，是**视觉正确性**：`NSVisualEffectView` 的材质会把
    /// 背景色去饱和、往中性灰拉，暖纸底一进材质就发灰，朱红也会被稀释。
    /// 纸的整个质感来自"没有中间介质"——底色就是底色。
    ///
    /// 三个开关必须同时关：`enabled` 只管内容区，`sidebarEnabled` 管侧栏
    /// （`SharedSidebarComponents.SidebarBackground`），`inputEnabled` 管输入卡
    /// （`FloatingInputCard:6241`）。只关 `enabled` 会留下半块毛玻璃。
    ///
    /// 其余参数刻意保留旧值：用户在主题编辑器里重新打开玻璃时，
    /// 拿到的是可用的一组值，而不是一堆 0。
    static let paperGlass = ThemeGlass(
        enabled: false,
        sidebarEnabled: false,
        inputEnabled: false,
        material: .windowBackground,
        blurRadius: 20,
        opacityPrimary: 0.78,
        opacitySecondary: 0.62,
        opacityTertiary: 0.45,
        tintColor: "#FFFFFF",
        tintOpacity: 0.08,
        edgeLight: "#FFFFFFCC",
        windowBackingOpacity: 0.92
    )

    /// 夜纸同理。深色下材质会把桌面颜色渗进来，
    /// 一块暖黑的"纸"不该随壁纸变色。
    static let nightGlass = ThemeGlass(
        enabled: false,
        sidebarEnabled: false,
        inputEnabled: false,
        material: .windowBackground,
        blurRadius: 20,
        opacityPrimary: 0.82,
        opacitySecondary: 0.68,
        opacityTertiary: 0.50,
        tintColor: "#000000",
        tintOpacity: 0.12,
        edgeLight: "#FFFFFF30",
        windowBackingOpacity: 0.94
    )

    // MARK: - 工具

    /// 令牌层存的是不带 `#` 的 `RRGGBB`；主题 JSON 与 `Color(themeHex:)` 都接受两种，
    /// 但带 `#` 的可读性更好，也和仓库里既有的主题 JSON 一致。
    private static func hex(_ value: String) -> String {
        value.hasPrefix("#") ? value : "#" + value
    }
}
