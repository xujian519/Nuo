//
//  NuoColor.swift
//  NuoDesignSystem
//
//  色彩系统。
//
//  设计原则（读代码前先读这一段）：
//
//  1. 这套界面只有两个"颜色"：纸（暖中性灰阶）与朱（印泥红）。
//     其余所有色值都是纸的深浅变化，或朱的透明度变化。
//  2. 朱红是稀缺资源。它只允许出现在两类时刻：
//       · 存在（presence）—— 智能体正在听、正在想、正在说
//       · 承诺（commit）—— 用户按下发送、确认授权、盖章落定
//     把朱红用在装饰上（边框、图标、标题）会立刻让界面变成廉价国潮。
//  3. 危险色与朱红同族，这是刻意的：界面上"红"代表"重要"。
//     因此**错误状态绝不允许只靠颜色传达**，必须同时带图标与文字。
//     见 DESIGN_SPEC.md §2.4 的对比度与冗余编码规则。
//  4. 所有色值都成对定义（light/dark），通过 NSColor 动态解析，
//     组件里不要写 `if colorScheme == .dark` 分支。
//

import AppKit
import SwiftUI

// MARK: - Hex 解析

extension NSColor {
    /// 从 `#RRGGBB` 或 `RRGGBB` 构造 sRGB 颜色。非法输入返回品红，
    /// 这样错误在视觉上立刻暴露，而不是静默变黑。
    convenience init(nuoHex hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            self.init(srgbRed: 1, green: 0, blue: 1, alpha: 1)
            return
        }
        self.init(
            srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
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
    public static let paperSunken = NuoDynamicColor(light: "#EFEAE0", dark: "#100F0C")
    public static let paper = NuoDynamicColor(light: "#F7F4ED", dark: "#161512")
    public static let paperRaised = NuoDynamicColor(light: "#FCFAF6", dark: "#1E1C18")
    public static let paperFloat = NuoDynamicColor(light: "#FFFFFF", dark: "#26231E")

    // ── 墨：文字与线条 ────────────────────────────────────────────
    public static let ink = NuoDynamicColor(light: "#1C1A17", dark: "#F2EEE4")
    public static let inkSecondary = NuoDynamicColor(light: "#565149", dark: "#ADA69A")
    /// light 对纸 4.98:1、dark 5.04:1 —— 三级文字也过 AA 正文线。
    public static let inkTertiary = NuoDynamicColor(light: "#6F6959", dark: "#8C8679")
    /// 对纸仅 2.88:1。**只用于非文字装饰**。
    public static let inkGhost = NuoDynamicColor(light: "#98907F", dark: "#5F5A53")

    // ── 发丝线 ────────────────────────────────────────────────────
    public static let hairline = NuoDynamicColor(light: "#E2DCD0", dark: "#2C2925")
    public static let hairlineStrong = NuoDynamicColor(light: "#CFC7B8", dark: "#3A362F")

    // ── 朱：印泥 ──────────────────────────────────────────────────
    /// 品牌主色。light 4.64:1 / dark 5.32:1。
    public static let cinnabar = NuoDynamicColor(light: "#C93A2B", dark: "#EB5B45")
    public static let cinnabarDeep = NuoDynamicColor(light: "#A32C20", dark: "#C9472F")
    /// 次要强调（徽标着色）。图形色，不作正文字色。
    public static let cinnabarLight = NuoDynamicColor(light: "#D9564A", dark: "#F47B63")
    public static let cinnabarWash = NuoDynamicColor(light: "#F3E2DE", dark: "#3A211C")
    public static let cinnabarBloom = NuoDynamicColor(light: "#FAF0ED", dark: "#241714")

    // ── 状态 ──────────────────────────────────────────────────────
    public static let success = NuoDynamicColor(light: "#3F7A42", dark: "#6FAE72")
    public static let warning = NuoDynamicColor(light: "#9A6414", dark: "#D9A24B")
    /// 墨红：比朱深、比朱冷。错误必须同时靠图标与文字编码。
    public static let danger = NuoDynamicColor(light: "#8E2F22", dark: "#F0715C")
    public static let info = NuoDynamicColor(light: "#565149", dark: "#ADA69A")

    // ── 存在态专用 ────────────────────────────────────────────────
    /// 说话态。对纸 3.01:1 —— **纯图形色，不用于文字。**
    public static let amber = NuoDynamicColor(light: "#C97B24", dark: "#F0A94A")
    public static let emberCore = NuoDynamicColor(light: "#5E2418", dark: "#7B2E1E")

    // ── 代码块（唯一允许的冷色域）────────────────────────────────
    public static let codeBackground = NuoDynamicColor(light: "#F1EDE3", dark: "#121110")
    public static let codeBorder = NuoDynamicColor(light: "#E0D9CA", dark: "#2A2723")
    public static let codeKeyword = NuoDynamicColor(light: "#8E2F22", dark: "#E88C79")
    public static let codeString = NuoDynamicColor(light: "#3F7A42", dark: "#8FC292")
    public static let codeComment = NuoDynamicColor(light: "#8B8578", dark: "#6F695F")
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
