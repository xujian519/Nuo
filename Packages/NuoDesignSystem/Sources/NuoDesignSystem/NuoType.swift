//
//  NuoType.swift
//  NuoDesignSystem
//
//  字体系统。
//
//  只使用系统字体，不打包任何字体文件——这是"纯 Swift、零资源依赖"的一部分，
//  也让中文（PingFang SC）与西文（SF Pro）在同一行里的基线由系统保证。
//
//  三条纪律：
//
//  1. **正文用 15pt / 行高 24**。中英混排的可读性拐点在 15–16pt，
//     14pt 在西文里舒服，中文会糊；24 的行高 = 1.6 倍，是中文长文的下限。
//  2. **长行不超过 68 个字符**（约 680pt @15pt）。对话正文栏宽上限见 `NuoMetrics.readingColumn`。
//  3. **衬线只用于品牌时刻**：印章旁的题字、启动页的标语、空状态的一句话。
//     正文、按钮、标签一律无衬线。衬线用多了就变成"文艺小程序"。
//

import SwiftUI

// MARK: - 字号角色

/// 一个完整的文字样式：字族 + 字号 + 字重 + 字距 + 行距。
///
/// 字距（tracking）在大字号下必须为负值，否则中文标题会显得松垮；
/// 小字号下必须为 0 或微正，否则会糊。
public struct NuoTypeStyle {
    public let size: CGFloat
    public let weight: Font.Weight
    public let design: Font.Design
    /// 字距，单位 pt。
    public let tracking: CGFloat
    /// 额外行距（SwiftUI 的 lineSpacing 是在默认行高之上叠加的），单位 pt。
    public let lineSpacing: CGFloat

    public init(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        tracking: CGFloat = 0,
        lineSpacing: CGFloat = 0
    ) {
        self.size = size
        self.weight = weight
        self.design = design
        self.tracking = tracking
        self.lineSpacing = lineSpacing
    }

    public var font: Font {
        .system(size: size, weight: weight, design: design)
    }
}

// MARK: - 字阶

public enum NuoType {

    /// 品牌大标。只用于启动页与"关于"。
    public static let display = NuoTypeStyle(size: 40, weight: .semibold, tracking: -0.8, lineSpacing: 2)
    /// 页面主标题。
    public static let title1 = NuoTypeStyle(size: 26, weight: .semibold, tracking: -0.4, lineSpacing: 2)
    /// 分组标题、Sheet 标题。
    public static let title2 = NuoTypeStyle(size: 18, weight: .semibold, tracking: -0.2, lineSpacing: 1)
    /// 卡片标题、消息发送者。
    public static let headline = NuoTypeStyle(size: 15, weight: .semibold, tracking: -0.1, lineSpacing: 1)
    /// 正文。对话内容就是它。
    public static let body = NuoTypeStyle(size: 15, weight: .regular, lineSpacing: 5)
    /// 正文强调（正文内的加粗片段用它保持行高一致）。
    public static let bodyStrong = NuoTypeStyle(size: 15, weight: .medium, lineSpacing: 5)
    /// 次级正文。列表副标题、说明文字。
    public static let callout = NuoTypeStyle(size: 13, weight: .regular, lineSpacing: 3)
    /// 元信息。时间戳、字数、模型名。
    public static let caption = NuoTypeStyle(size: 12, weight: .regular, tracking: 0.1, lineSpacing: 2)
    /// 元信息·强调。分组头、状态。带轻微正字距，小字号需要它来"立住"。
    public static let captionStrong = NuoTypeStyle(size: 12, weight: .semibold, tracking: 0.4, lineSpacing: 2)

    /// 代码 / 数值。等宽让数字对齐，也让 token 计数不跳动。
    public static let mono = NuoTypeStyle(size: 13, weight: .regular, design: .monospaced, lineSpacing: 3)
    /// 代码块正文。
    public static let code = NuoTypeStyle(size: 13, weight: .regular, design: .monospaced, lineSpacing: 4)

    /// 衬线题字。品牌时刻专用。
    public static let sealSerif = NuoTypeStyle(
        size: 17,
        weight: .regular,
        design: .serif,
        tracking: 1.6,
        lineSpacing: 6
    )
    /// 衬线标语。启动页那一句话。
    public static let taglineSerif = NuoTypeStyle(
        size: 22,
        weight: .regular,
        design: .serif,
        tracking: 0.8,
        lineSpacing: 8
    )

    /// 按钮文字。
    public static let button = NuoTypeStyle(size: 13, weight: .medium, tracking: 0.1)
}

// MARK: - 应用器

extension View {
    /// 把一档字阶应用到任意文本容器上（含字距与行距）。
    ///
    /// 注意：`lineSpacing` 只影响多行；单行文本不会有副作用。
    public func nuoType(_ style: NuoTypeStyle) -> some View {
        self
            .font(style.font)
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
    }
}

// MARK: - 数字变化

/// 数字滚动。用于 token 计数、延迟、金额这类会跳变的数值。
///
/// 一个细节：直接让 Text 数字跳变会让整行宽度抖动，
/// 所以这里固定等宽数字字形（`.monospacedDigit()`）。
public struct NuoNumberText: View {
    private let value: String
    private let style: NuoTypeStyle
    private let color: Color

    public init(_ value: String, style: NuoTypeStyle = NuoType.mono, color: Color = NuoColor.textSecondary) {
        self.value = value
        self.style = style
        self.color = color
    }

    public init(_ value: Int, style: NuoTypeStyle = NuoType.mono, color: Color = NuoColor.textSecondary) {
        self.init(String(value), style: style, color: color)
    }

    public var body: some View {
        Text(value)
            .nuoType(style)
            .monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(.numericText())
    }
}
