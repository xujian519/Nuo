//
//  NuoSurface.swift
//  NuoDesignSystem
//
//  材质与容器。
//
//  这套界面拒绝"卡片堆叠"。所有容器分三类，且**不允许混用**：
//
//  · **画布（canvas）**——铺满，无边框无阴影。对话区、列表区。
//  · **面（surface）**——抬升一层，1px 发丝线，无阴影。卡片、消息块。
//  · **浮层（float）**——离开画布，有阴影 + 更实的底。dock、Popover、Sheet。
//
//  判据很简单：**它会跟着滚动一起移动吗？**
//  会 → 面；不会 → 浮层。
//

import SwiftUI

// MARK: - 纸纤维

/// 宣纸的纤维纹理。
///
/// 为什么用代码画而不是贴图：打包一张 2x 的噪点 png 会多 200–400KB，
/// 而且缩放时会摩尔纹。这里用固定种子的伪随机短线，在 Canvas 里一次性绘制，
/// 不同尺寸重新生成（有缓存），视觉上是"纸的横向纤维"而不是电视雪花。
public struct NuoPaperGrain: View {
    private let intensity: Double
    private let fiberCount: Int

    /// - Parameters:
    ///   - intensity: 0.0–1.0，建议 0.10–0.25。超过 0.35 会显脏。
    ///   - fiberCount: 纤维条数。默认按面积自适应。
    public init(intensity: Double = 0.16, fiberCount: Int = 0) {
        self.intensity = intensity
        self.fiberCount = fiberCount
    }

    public var body: some View {
        Canvas { context, size in
            var rng = NuoSeededRandom(seed: 0x9E37_79B9)
            let count =
                fiberCount > 0
                ? fiberCount
                : max(300, Int(size.width * size.height / 900))
            let ink = NuoPalette.ink

            for _ in 0 ..< count {
                let x = rng.next() * size.width
                let y = rng.next() * size.height
                // 纤维长度 2–14pt，绝大多数很短——长纤维会变成划痕。
                let length = 2 + rng.next() * 12
                let lift = (rng.next() - 0.5) * 1.2
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x + length, y: y + lift))
                // 每条纤维的透明度再随机一次，避免出现均匀的"网"。
                let alpha = intensity * 0.10 * (0.4 + rng.next())
                context.stroke(
                    path,
                    with: .color(ink.opacity(alpha)),
                    lineWidth: 0.5
                )
            }
        }
        .allowsHitTesting(false)
        .blendMode(.multiply)
        .drawingGroup()
    }
}

/// 确定性伪随机（SplitMix64）。同一尺寸永远画同一张纸 —— 避免重绘时"沙沙"抖动。
struct NuoSeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double((state >> 11) & 0xFFFF_FFFF) / Double(0xFFFF_FFFF)
    }
}

// MARK: - 表面修饰

extension View {
    /// 画布：铺满、无边框。
    public func nuoCanvas() -> some View {
        self.background(NuoColor.canvas)
    }

    /// 面：抬升一层的卡片。带发丝线，不带阴影。
    public func nuoSurface(
        radius: CGFloat = NuoRadius.card,
        fill: Color? = nil,
        border: Color? = nil
    ) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill ?? NuoColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(border ?? NuoColor.separator, lineWidth: NuoStroke.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// 浮层：离开画布。阴影 + 更实的底。
    public func nuoFloat(
        radius: CGFloat = NuoRadius.dock,
        level: NuoElevation = .mid
    ) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(NuoColor.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(NuoColor.separator, lineWidth: NuoStroke.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .nuoElevation(level)
    }

    /// 某一条边上的发丝线。比 `Divider()` 更可控（Divider 在某些容器里会变 2px）。
    public func nuoHairline(_ edge: Edge, inset: CGFloat = 0) -> some View {
        overlay(alignment: edge.alignment) {
            NuoHairline()
                .padding(
                    edge == .top || edge == .bottom
                        ? .horizontal
                        : .vertical,
                    inset
                )
        }
    }

    /// 焦点环。键盘导航与 VoiceOver 可见时使用。
    public func nuoFocusRing(_ isFocused: Bool, radius: CGFloat = NuoRadius.control) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius + 2, style: .continuous)
                .strokeBorder(
                    NuoColor.focusRing.opacity(isFocused ? 0.55 : 0),
                    lineWidth: NuoStroke.focus
                )
                .padding(-2)
        )
    }
}

/// 一条 1pt 的发丝线。
public struct NuoHairline: View {
    private let color: Color
    private let vertical: Bool

    public init(color: Color = NuoColor.separator, vertical: Bool = false) {
        self.color = color
        self.vertical = vertical
    }

    public var body: some View {
        Rectangle()
            .fill(color)
            .frame(
                width: vertical ? NuoStroke.hairline : nil,
                height: vertical ? nil : NuoStroke.hairline
            )
    }
}

private extension Edge {
    var alignment: Alignment {
        switch self {
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }
}

// MARK: - 毛玻璃

/// 顶部栏与浮层的玻璃底。
///
/// 只在**有内容从下面穿过**的地方用（标题栏、图层顶部）。
/// 平铺背景上用毛玻璃是纯浪费 GPU，且会让纸的暖调变灰。
public struct NuoGlassBar<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .background(.ultraThinMaterial)
            .background(NuoColor.canvas.opacity(0.55))
            .overlay(alignment: .bottom) {
                NuoHairline()
            }
    }
}
