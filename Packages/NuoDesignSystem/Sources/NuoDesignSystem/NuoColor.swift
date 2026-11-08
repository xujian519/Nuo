//
//  NuoColor.swift
//  NuoDesignSystem
//
//  色彩系统。
//
//  设计原则（读代码前先读这一段）：
//
//  1. 色值全部来自 **Radix Colors**（MIT 开源）的 12 级色阶，不自造色值。
//     每个令牌都注明取自哪条色阶的第几级，便于核对与二次调校。
//  2. 这套界面只有两个色相：中性灰（纸）与朱（印泥红）。
//     其余所有色值都是灰阶的深浅变化，或朱红的透明度变化。
//  3. 朱红是稀缺资源。它只允许出现在两类时刻：
//       · 存在（presence）—— 智能体正在听、正在想、正在说
//       · 承诺（commit）—— 用户按下发送、确认授权、盖章落定
//     把朱红用在装饰上（边框、图标、标题）会立刻让界面变成廉价国潮。
//  4. 危险色与朱红同族，这是刻意的：界面上"红"代表"重要"。
//     因此**错误状态绝不允许只靠颜色传达**，必须同时带图标与文字。
//     见 DESIGN_SPEC.md §2.4 的对比度与冗余编码规则。
//  5. 所有色值都成对定义（light/dark），通过 NSColor 动态解析，
//     组件里不要写 `if colorScheme == .dark` 分支。
//
//  Radix 色阶编号约定（官方语义）：
//    1      应用底色          2-5    组件底色 / 悬浮 / 选中
//    6-8    边框与分隔线       9      实心底色
//    10     实心悬浮态        11     低对比文字
//    12     高对比文字
//  深色模式用同名 `*-dark` 色阶，同步号在深浅两套里承担同一个语义角色。
//
//  本文件采用的色阶与理由：
//    · 中性层用 **sand**（暖灰）而不是 gray（纯中性）：
//      纯中性会把"纸"的暖调洗掉，sand 保留宣纸的温。
//    · 强调色用 **tomato**：与朱红同色相家族，保住"朱红 = 存在 / 承诺"
//      的品牌纪律（DESIGN_SPEC §2.2 的"红 = 重要"双重编码仍然成立）。
//    · 状态色用 green / amber / red，危险色用 red 而不是 tomato，
//      这样错误色与强调色在色相上仍可分辨。
//    · 浅色底的 12 级色阶里只有 11、12 两级过 AA 正文线，
//      所以**浅色模式的状态文字一律取第 12 级**，深色模式取第 11 级。
//      这是刻意的"深浅反转"：浅底上的状态色要沉下去，深底上的要亮起来。
//    · 三级文字用 sand-12 按 alpha 派生（Radix 自带同名 `*-a` 透明度色阶，
//      这里是同构用法），这样三级文字既比二级淡、又仍然过 AA 正文线。
//
//

import AppKit
import SwiftUI

// MARK: - Hex 解析

extension NSColor {
    /// 从 `#RRGGBB` / `RRGGBB` / `#RRGGBBAA` / `RRGGBBAA` 构造 sRGB 颜色。
    /// 非法输入返回品红，这样错误在视觉上立刻暴露，而不是静默变黑。
    ///
    /// 8 位形式是 **RRGGBBAA**（alpha 在尾部），与主题系统
    /// `Color(themeHex:)` 的解析顺序一致。令牌层用它承载"同一色相的
    /// 透明度变体"（例如三级文字 = sand-12 @ 65%）。
    convenience init(nuoHex hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt32(s, radix: 16) else {
            self.init(srgbRed: 1, green: 0, blue: 1, alpha: 1)
            return
        }
        let alpha = s.count == 8 ? CGFloat(v & 0xFF) / 255 : 1
        let rgb = s.count == 8 ? v >> 8 : v
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}

// MARK: - 动态色

/// 一对 light/dark 色值，运行时按当前 NSAppearance 解析。
///
/// 不把颜色拆成两套 Theme 的原因是：SwiftUI 的 `@Environment(\.colorScheme)`
/// 在 Sheet / Popover / 独立 NSWindow 里可能落后一帧，导致顶栏与内容背景
/// 出现一瞬间的错色。交给 AppKit 的 appearance 解析没有这个问题。
public struct NuoDynamicColor: Sendable {
    public let light: String
    public let dark: String

    public init(light: String, dark: String) {
        self.light = light
        self.dark = dark
    }

    public var color: Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(nuoHex: isDark ? dark : light)
            }
        )
    }
}

// MARK: - 调色板

/// 色阶的原始定义：一对 light/dark 十六进制。
///
/// 这是整个仓库里十六进制的**唯一真源**。
///  · 设计系统内部：`NuoPalette` 把它包成 SwiftUI `Color`；
///  · 产品侧（CustomTheme / 主题 JSON）：直接读 `.light` / `.dark` 字符串。
///
/// 两层分开的原因是主题系统只认 `String`，而视图只认 `Color`。
/// 如果只提供 `Color`，产品侧就得把色值抄一遍——那正是要避免的漂移。
public enum NuoHex {

    // ── 纸：从最深的凹陷到最亮的浮起 ──────────────────────────────
    /// 凹陷面（侧栏底、三级底）。sand-3 / sand-1。
    public static let paperSunken = NuoDynamicColor(light: "#F1F0EF", dark: "#111110")
    /// 画布。sand-2 / sand-2。
    public static let paper = NuoDynamicColor(light: "#F9F9F8", dark: "#191918")
    /// 抬升面（卡片、二级底）。sand-1 / sand-3。
    public static let paperRaised = NuoDynamicColor(light: "#FDFDFC", dark: "#222221")
    /// 浮起面（按钮、输入框、浮层）。Radix 浅色浮层用纯白 / sand-4。
    public static let paperFloat = NuoDynamicColor(light: "#FFFFFF", dark: "#2A2A28")

    // ── 墨：文字与线条 ────────────────────────────────────────────
    /// 正文。sand-12。浅色 15.5:1，深色 15.1:1。
    public static let ink = NuoDynamicColor(light: "#21201C", dark: "#EEEEEC")
    /// 次级文字。sand-11。浅色 5.7:1，深色 8.4:1。
    public static let inkSecondary = NuoDynamicColor(light: "#63635E", dark: "#B5B3AD")
    /// 三级文字：sand-12 @ 65%（Radix 同名 `*-a` 透明度色阶的同构用法）。
    /// 合成后浅色 5.0:1、深色 7.1:1，仍然过 AA 正文线。
    public static let inkTertiary = NuoDynamicColor(light: "#21201CA6", dark: "#EEEEECA6")
    /// 对纸仅 3.2:1。**只用于非文字装饰**，不得承载正文。
    public static let inkGhost = NuoDynamicColor(light: "#8D8D86", dark: "#62605B")

    // ── 发丝线 ────────────────────────────────────────────────────
    /// 分隔线（装饰性）。sand-6。
    public static let hairline = NuoDynamicColor(light: "#DAD9D6", dark: "#3B3A37")
    /// 组件边界（输入框、按钮边框）。sand-10。
    /// 浅色 3.7:1、深色 4.1:1，满足 UI 组件边界 ≥3:1。
    public static let hairlineStrong = NuoDynamicColor(light: "#82827C", dark: "#7C7B74")

    // ── 朱：印泥 ──────────────────────────────────────────────────
    /// 品牌主色。tomato-11 / tomato-10。
    /// 浅色对画布 4.73:1、白字 4.98:1；深色对画布 5.32:1、黑字 6.36:1。
    public static let cinnabar = NuoDynamicColor(light: "#D13415", dark: "#EC6142")
    /// 更深一档（按下态）。tomato-12 / tomato-9。
    public static let cinnabarDeep = NuoDynamicColor(light: "#5C271F", dark: "#E54D2E")
    /// 更浅一档（徽标着色）。tomato-10 / tomato-11。图形色，不作正文字色。
    public static let cinnabarLight = NuoDynamicColor(light: "#DD4425", dark: "#FF977D")
    /// 朱红浅底（选中行）。tomato-3 / tomato-5。
    public static let cinnabarWash = NuoDynamicColor(light: "#FEEBE7", dark: "#5E1C16")
    /// 朱红最浅底（强调晕染）。tomato-2 / tomato-3。
    public static let cinnabarBloom = NuoDynamicColor(light: "#FFF8F7", dark: "#391714")

    // ── 状态 ──────────────────────────────────────────────────────
    /// 成功。green-12 / green-11。
    /// 浅色底只有第 12 级过 AA 正文线，深色底第 11 级最亮。
    public static let success = NuoDynamicColor(light: "#193B2D", dark: "#3DD68C")
    /// 警告。amber-12 / amber-11。
    public static let warning = NuoDynamicColor(light: "#4F3422", dark: "#FFCA16")
    /// 墨红：比朱深、比朱冷。错误必须同时靠图标与文字编码。
    /// red-12 / red-11。
    public static let danger = NuoDynamicColor(light: "#641723", dark: "#FF9592")
    /// 信息态不引入蓝色，用二级墨色表达。
    public static let info = NuoDynamicColor(light: "#63635E", dark: "#B5B3AD")

    // ── 存在态专用 ────────────────────────────────────────────────
    /// 说话态。orange-11 / orange-10 —— Radix 的 amber 色阶在浅色底上
    /// 过不了 3:1 图形线，所以浅色侧改用 orange 色阶。
    /// **纯图形色，不用于文字。**
    public static let amber = NuoDynamicColor(light: "#CC4E00", dark: "#FF801F")
    /// 发光核：有意做得比画布更暗，是渐变的中心而不是边界。
    /// tomato-12 / tomato-6。
    public static let emberCore = NuoDynamicColor(light: "#5C271F", dark: "#6E2920")

    // ── 代码块（唯一允许的冷色域）────────────────────────────────
    /// 代码底。sand-3 / sand-1。
    public static let codeBackground = NuoDynamicColor(light: "#F1F0EF", dark: "#111110")
    /// 代码块边界。sand-6。
    public static let codeBorder = NuoDynamicColor(light: "#DAD9D6", dark: "#3B3A37")
    /// 关键字。tomato-12 / tomato-11。
    public static let codeKeyword = NuoDynamicColor(light: "#5C271F", dark: "#FF977D")
    /// 字符串。green-12 / green-11。
    public static let codeString = NuoDynamicColor(light: "#193B2D", dark: "#3DD68C")
    /// 注释。sand-11 / sand-11。
    public static let codeComment = NuoDynamicColor(light: "#63635E", dark: "#B5B3AD")
}

/// 色阶的 SwiftUI 视图：与 `NuoHex` 一一对应，只做 `.color`。
/// 命名为"材料"而不是"用途"：纸有六层深浅，墨有四层浓度，朱有四档强度。
public enum NuoPalette {

    public static let paperSunken = NuoHex.paperSunken.color
    public static let paper = NuoHex.paper.color
    public static let paperRaised = NuoHex.paperRaised.color
    public static let paperFloat = NuoHex.paperFloat.color

    public static let ink = NuoHex.ink.color
    public static let inkSecondary = NuoHex.inkSecondary.color
    public static let inkTertiary = NuoHex.inkTertiary.color
    public static let inkGhost = NuoHex.inkGhost.color

    public static let hairline = NuoHex.hairline.color
    public static let hairlineStrong = NuoHex.hairlineStrong.color

    public static let cinnabar = NuoHex.cinnabar.color
    public static let cinnabarDeep = NuoHex.cinnabarDeep.color
    public static let cinnabarLight = NuoHex.cinnabarLight.color
    public static let cinnabarWash = NuoHex.cinnabarWash.color
    public static let cinnabarBloom = NuoHex.cinnabarBloom.color

    public static let success = NuoHex.success.color
    public static let warning = NuoHex.warning.color
    public static let danger = NuoHex.danger.color
    public static let info = NuoHex.info.color

    public static let amber = NuoHex.amber.color
    public static let emberCore = NuoHex.emberCore.color

    public static let codeBackground = NuoHex.codeBackground.color
    public static let codeBorder = NuoHex.codeBorder.color
    public static let codeKeyword = NuoHex.codeKeyword.color
    public static let codeString = NuoHex.codeString.color
    public static let codeComment = NuoHex.codeComment.color
}

// MARK: - 语义别名

/// 组件层只读这一层，不直接摸 `NuoPalette`。
/// 好处：换肤 / 换品牌时只改映射，不动组件。
public enum NuoColor {
    // 表面
    public static let canvas = NuoPalette.paper
    public static let surface = NuoPalette.paperRaised
    public static let surfaceElevated = NuoPalette.paperFloat
    public static let surfaceSunken = NuoPalette.paperSunken

    // 文字
    public static let textPrimary = NuoPalette.ink
    public static let textSecondary = NuoPalette.inkSecondary
    public static let textTertiary = NuoPalette.inkTertiary
    public static let textPlaceholder = NuoPalette.inkGhost

    // 线
    public static let separator = NuoPalette.hairline
    public static let border = NuoPalette.hairlineStrong
    public static let focusRing = NuoPalette.cinnabar

    // 强调
    public static let accent = NuoPalette.cinnabar
    public static let accentPressed = NuoPalette.cinnabarDeep
    public static let accentWash = NuoPalette.cinnabarWash
    public static let accentBloom = NuoPalette.cinnabarBloom

    // 语义
    public static let success = NuoPalette.success
    public static let warning = NuoPalette.warning
    public static let danger = NuoPalette.danger
    public static let info = NuoPalette.info

    // 选择高亮（跟随系统，避免和朱冲突）
    public static let selection = Color(nsColor: .selectedTextBackgroundColor)
}
