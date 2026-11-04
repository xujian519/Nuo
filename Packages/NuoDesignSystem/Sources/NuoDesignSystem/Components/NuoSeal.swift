//
//  NuoSeal.swift
//  NuoDesignSystem
//
//  印章。
//
//  「诺」这个字的意思是"答应下来的事"。印章是"答应"的物证——
//  盖下去就不再改。这套界面里，印章只允许出现在三个地方：
//
//  1. 侧栏顶部 / 标题栏左侧的**身份**位——它代表"这是谁在跟你说话"。
//  2. 首次启动、关于面板的**品牌**位。
//  3. 完成、落定、归档等**仪式**时刻（配合 `NuoStampEffect`）。
//
//  不要在普通按钮、标签、空状态插画里放印章。印章一旦变成装饰，
//  它的重量就没了。
//
//  绘制方式：Canvas 手绘，不依赖任何图片资源。这样它在任何倍率下都是
//  矢量清晰的，也不给"纯 Swift、零资源"的原则开一个口子。
//

import SwiftUI

// MARK: - 印章样式

public enum NuoSealStyle {
    /// 朱文：红底、白字。视觉重量最大，用于品牌位。
    case filled
    /// 白文：只有红边与红字，中间留纸色。用于侧栏这类需要轻的地方。
    case outline
    /// 淡印：朱红降到 28%。用于背景水印、空状态。
    case watermark
}

// MARK: - 印章

/// 可参数化的印章。默认画「诺」。
///
/// 结构是：印边（双线） + 四角回纹 + 中心字。
public struct NuoSealMark: View {
    private let glyph: String
    private let style: NuoSealStyle
    private let size: CGFloat
    private let tint: Color

    public init(
        glyph: String = "诺",
        style: NuoSealStyle = .filled,
        size: CGFloat = NuoMetrics.seal,
        tint: Color = NuoPalette.cinnabar
    ) {
        self.glyph = glyph
        self.style = style
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let side = min(canvasSize.width, canvasSize.height)
            let rect = CGRect(
                x: (canvasSize.width - side) / 2,
                y: (canvasSize.height - side) / 2,
                width: side,
                height: side
            )
            drawSeal(in: &context, rect: rect, side: side)
        }
        .frame(width: size, height: size)
        // 印章是图形，必须让 VoiceOver 读出它的含义，而不是"图片"。
        .accessibilityElement()
        .accessibilityLabel(Text("Nuo 印"))
        .accessibilityAddTraits(.isImage)
    }

    private func drawSeal(in context: inout GraphicsContext, rect: CGRect, side: CGFloat) {
        let paper = NuoPalette.paperRaised
        let alpha: Double
        switch style {
        case .filled: alpha = 1.0
        case .outline: alpha = 1.0
        case .watermark: alpha = 0.28
        }

        let inkColor = tint.opacity(alpha)

        // ── 底 ──────────────────────────────────────────────
        if style == .filled {
            let outer = Path(roundedRect: rect, cornerRadius: side * 0.075)
            context.fill(outer, with: .color(inkColor))
        } else {
            // 白文：只有边。
            let lineWidth = max(1, side * 0.055)
            let outer = Path(
                roundedRect: rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
                cornerRadius: side * 0.075
            )
            context.stroke(outer, with: .color(inkColor), lineWidth: lineWidth)
        }

        // ── 印边内侧的第二道细线（形成"印"的双边质感）──────────
        let innerInset = side * 0.115
        let innerRect = rect.insetBy(dx: innerInset, dy: innerInset)
        let innerLine = Path(roundedRect: innerRect, cornerRadius: side * 0.02)
        context.stroke(
            innerLine,
            with: .color(style == .filled ? paper.opacity(0.92 * alpha) : inkColor.opacity(0.55)),
            lineWidth: max(0.75, side * 0.028)
        )

        // ── 四角回纹 ────────────────────────────────────────
        let cornerInset = side * 0.155
        let armLength = side * 0.135
        let motifColor = style == .filled ? paper.opacity(0.9 * alpha) : inkColor.opacity(0.75)
        for corner in [Corner.topLeading, .topTrailing, .bottomLeading, .bottomTrailing] {
            drawMeander(
                in: &context,
                corner: corner,
                rect: rect,
                inset: cornerInset,
                arm: armLength,
                color: motifColor,
                lineWidth: max(0.9, side * 0.033)
            )
        }

        // ── 中心字 ──────────────────────────────────────────
        guard !glyph.isEmpty else { return }
        let glyphSize = side * 0.46
        let text = Text(glyph)
            .font(.system(size: glyphSize, weight: .semibold, design: .serif))
            .foregroundStyle(style == .filled ? paper.opacity(0.96) : inkColor)
        context.draw(text, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
    }

    private enum Corner {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
    }

    /// 回纹：两个套叠的「L」。
    ///
    /// 之所以只画 L 而不画完整的方形螺旋：在 22pt 的尺寸下，
    /// 完整螺旋会糊成一团墨。L 形在任何尺寸下都还认得出是回纹。
    private func drawMeander(
        in context: inout GraphicsContext,
        corner: Corner,
        rect: CGRect,
        inset: CGFloat,
        arm: CGFloat,
        color: Color,
        lineWidth: CGFloat
    ) {
        var path = Path()

        // 局部坐标系：以该角为原点，x 向右（或向左），y 向下（或向上）。
        let xFlip: CGFloat = (corner == .topTrailing || corner == .bottomTrailing) ? -1 : 1
        let yFlip: CGFloat = (corner == .bottomLeading || corner == .bottomTrailing) ? -1 : 1

        let originX =
            corner == .topTrailing || corner == .bottomTrailing
            ? rect.maxX - inset
            : rect.minX + inset
        let originY =
            corner == .bottomLeading || corner == .bottomTrailing
            ? rect.maxY - inset
            : rect.minY + inset

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * xFlip, y: originY + y * yFlip)
        }

        // 外 L
        path.move(to: point(0, arm))
        path.addLine(to: point(0, 0))
        path.addLine(to: point(arm, 0))

        // 内 L（缩进 40%）
        let innerArm = arm * 0.58
        let innerInset = arm * 0.38
        path.move(to: point(innerInset, innerArm + innerInset))
        path.addLine(to: point(innerInset, innerInset))
        path.addLine(to: point(innerArm + innerInset, innerInset))

        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }
}

// MARK: - 盖章动效

/// 仪式时刻的盖章效果：从 1.6 倍砸下来，带极短的震动。
///
/// 用法：把 `isStamped` 从 false 翻到 true，印章出现并落定。
/// 不要把它用在普通的"保存成功"上——一天盖三次章，仪式就变成了噪音。
public struct NuoStampEffect<Content: View>: View {
    private let content: Content
    @State private var stamped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .scaleEffect(stamped ? 1 : 1.55)
            .opacity(stamped ? 1 : 0)
            .rotationEffect(.degrees(stamped ? 0 : -6))
            .onAppear {
                guard !reduceMotion else {
                    stamped = true
                    return
                }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.58)) {
                    stamped = true
                }
            }
    }
}

// MARK: - 身份位

/// 标题栏 / 侧栏顶部的「我 + 我在跟谁说话」。
///
/// 左边是 Nuo 的印，右边是当前智能体的名字与状态。
/// 状态点用光球而不是圆点，保持"活着"的一致性（见 PresenceOrb）。
public struct NuoIdentityBadge: View {
    private let agentName: String
    private let state: NuoPresenceState
    private let onTap: (() -> Void)?

    public init(
        agentName: String,
        state: NuoPresenceState = .idle,
        onTap: (() -> Void)? = nil
    ) {
        self.agentName = agentName
        self.state = state
        self.onTap = onTap
    }

    public var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: NuoSpace.sm) {
                NuoSealMark(style: .outline, size: NuoMetrics.sealSmall)
                VStack(alignment: .leading, spacing: 0) {
                    Text(agentName)
                        .nuoType(NuoType.captionStrong)
                        .foregroundStyle(NuoColor.textPrimary)
                        .lineLimit(1)
                    Text(state.label)
                        .nuoType(NuoType.caption)
                        .foregroundStyle(NuoColor.textTertiary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(NuoColor.textTertiary)
            }
            .padding(.horizontal, NuoSpace.sm)
            .padding(.vertical, NuoSpace.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("切换智能体")
    }
}
