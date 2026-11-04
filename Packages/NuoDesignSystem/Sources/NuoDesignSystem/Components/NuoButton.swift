//
//  NuoButton.swift
//  NuoDesignSystem
//
//  按钮与轻控件。
//
//  这套界面里按钮只有四种，且**层级靠"填充"而不是靠颜色**来区分：
//
//  · primary   —— 朱红实心。一个问题只允许有一个。发送、确认、开始。
//  · secondary —— 纸面 + 发丝线。常规操作。
//  · ghost     —— 无底无边。图标、行内操作、次要入口。
//  · destructive —— 空心 + 墨红文字。破坏性操作**永远不做实心红**，
//                   实心红会让误触的代价变大。
//
//  按下反馈统一是 scale 0.97 + 90ms，不要用颜色变深来表达按下——
//  颜色变化太慢，手上的感觉会断。
//

import SwiftUI

// MARK: - 层级

public enum NuoButtonRole {
    case primary
    case secondary
    case ghost
    case destructive
}

// MARK: - 按钮

public struct NuoButton<Label: View>: View {
    private let role: NuoButtonRole
    private let action: () -> Void
    private let label: Label
    private let fullWidth: Bool
    private let compact: Bool

    @State private var hovering = false
    @State private var pressed = false
    @Environment(\.isEnabled) private var isEnabled

    public init(
        role: NuoButtonRole = .secondary,
        fullWidth: Bool = false,
        compact: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.role = role
        self.action = action
        self.label = label()
        self.fullWidth = fullWidth
        self.compact = compact
    }

    public var body: some View {
        Button {
            action()
        } label: {
            label
                .nuoType(NuoType.button)
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, compact ? NuoSpace.sm : NuoSpace.md)
                .padding(.vertical, compact ? NuoSpace.xxs : NuoSpace.xs)
                .frame(minHeight: compact ? 22 : 28)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .background(background)
                .overlay(border)
                .clipShape(RoundedRectangle(cornerRadius: NuoRadius.control, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: NuoRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.97 : 1)
        .opacity(isEnabled ? 1 : 0.42)
        .onHover { hovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    withAnimation(NuoCurve.press) { pressed = true }
                }
                .onEnded { _ in
                    withAnimation(NuoCurve.snappy) { pressed = false }
                }
        )
        .animation(NuoCurve.snappy, value: hovering)
        .allowsHitTesting(isEnabled)
    }

    // MARK: 视觉

    private var foreground: Color {
        switch role {
        case .primary:
            // 朱底上的字用纸色，不用纯白——纯白在暖红上会发青。
            return NuoPalette.paperRaised
        case .secondary:
            return NuoColor.textPrimary
        case .ghost:
            return hovering ? NuoColor.textPrimary : NuoColor.textSecondary
        case .destructive:
            return NuoColor.danger
        }
    }

    @ViewBuilder
    private var background: some View {
        switch role {
        case .primary:
            RoundedRectangle(cornerRadius: NuoRadius.control, style: .continuous)
                .fill(hovering ? NuoColor.accentPressed : NuoColor.accent)
        case .secondary:
            RoundedRectangle(cornerRadius: NuoRadius.control, style: .continuous)
                .fill(hovering ? NuoPalette.paperFloat : NuoColor.surface)
        case .ghost:
            RoundedRectangle(cornerRadius: NuoRadius.control, style: .continuous)
                .fill(hovering ? NuoColor.surface : Color.clear)
        case .destructive:
            RoundedRectangle(cornerRadius: NuoRadius.control, style: .continuous)
                .fill(hovering ? NuoColor.danger.opacity(0.08) : Color.clear)
        }
    }

    @ViewBuilder
    private var border: some View {
        switch role {
        case .primary:
            EmptyView()
        case .secondary:
            RoundedRectangle(cornerRadius: NuoRadius.control, style: .continuous)
                .strokeBorder(NuoColor.separator, lineWidth: NuoStroke.hairline)
        case .ghost:
            EmptyView()
        case .destructive:
            RoundedRectangle(cornerRadius: NuoRadius.control, style: .continuous)
                .strokeBorder(
                    NuoColor.danger.opacity(hovering ? 0.5 : 0.28),
                    lineWidth: NuoStroke.hairline
                )
        }
    }
}

// MARK: - 图标按钮

/// 只有图标的按钮。热区强制 ≥ 28pt（`NuoMetrics.hitTarget`）。
public struct NuoIconButton: View {
    private let systemName: String
    private let help: String
    private let size: CGFloat
    private let tint: Color?
    private let action: () -> Void

    @State private var hovering = false
    @State private var pressed = false

    public init(
        systemName: String,
        help: String,
        size: CGFloat = 26,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.help = help
        self.size = size
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: NuoRadius.chip, style: .continuous)
                    .fill(hovering ? NuoColor.surface : Color.clear)
                Image(systemName: systemName)
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundStyle(tint ?? (hovering ? NuoColor.textPrimary : NuoColor.textSecondary))
            }
            .frame(
                width: max(size, NuoMetrics.hitTarget),
                height: max(size, NuoMetrics.hitTarget)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.94 : 1)
        .onHover { hovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(NuoCurve.press) { pressed = true } }
                .onEnded { _ in withAnimation(NuoCurve.snappy) { pressed = false } }
        )
        .animation(NuoCurve.quick, value: hovering)
        .help(help)
        .accessibilityLabel(Text(help))
    }
}

// MARK: - 发送键

/// 发送键。
///
/// 它是整个界面里"承诺"的代表，所以：
/// · 有内容时是朱红实心；无内容时是纸面空心（不是灰掉的实心——那像坏了）。
/// · 按下时有一圈扩散的朱色涟漪（`NuoSeal` 同族的"盖下去"手感）。
/// · 只有它允许出现 `⌘↩` 的提示，且提示只在悬停时出现。
public struct NuoSendButton: View {
    private let isEnabled: Bool
    private let isStreaming: Bool
    private let action: () -> Void

    @State private var hovering = false
    @State private var pressed = false
    @State private var ripple = false

    public init(isEnabled: Bool, isStreaming: Bool = false, action: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.isStreaming = isStreaming
        self.action = action
    }

    private var diameter: CGFloat { NuoMetrics.sendButton }

    public var body: some View {
        Button {
            guard isEnabled else { return }
            action()
            // 涟漪只在视觉层，不进状态机。
            ripple = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { ripple = false }
        } label: {
            ZStack {
                if ripple {
                    Circle()
                        .stroke(NuoColor.accent.opacity(0.35), lineWidth: 1.5)
                        .scaleEffect(1.5)
                        .opacity(0)
                        .animation(.easeOut(duration: 0.45), value: ripple)
                }

                Circle()
                    .fill(background)

                Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: diameter * 0.42, weight: .bold))
                    .foregroundStyle(foreground)
                    // 从箭头变成方块时轻微旋转，让"停止"显得果断。
                    .rotationEffect(.degrees(isStreaming ? 0 : 0))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: diameter, height: diameter)
            .overlay {
                if hovering && isEnabled {
                    Circle()
                        .strokeBorder(NuoColor.accent.opacity(0.35), lineWidth: 3)
                        .padding(-3)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.92 : 1)
        .onHover { hovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(NuoCurve.press) { pressed = true } }
                .onEnded { _ in withAnimation(NuoCurve.snappy) { pressed = false } }
        )
        .animation(NuoCurve.snappy, value: hovering)
        .animation(NuoCurve.snappy, value: isEnabled)
        .help(isStreaming ? "停止生成 (⌘.)" : "发送 (↩)")
        .accessibilityLabel(Text(isStreaming ? "停止生成" : "发送"))
    }

    private var background: Color {
        if isStreaming { return NuoColor.textPrimary }
        return isEnabled ? NuoColor.accent : NuoColor.surfaceSunken
    }

    private var foreground: Color {
        if isStreaming { return NuoPalette.paperRaised }
        return isEnabled ? NuoPalette.paperRaised : NuoColor.textTertiary
    }
}

// MARK: - 分段控件

/// 分段控件。用来切换"看得见的一组对等选项"（聊天 / 语音，模型档位）。
///
/// 选中态用**纸面 + 发丝线 + 极淡阴影**，不用朱红——
/// 朱红留给"承诺"，分段选择不是承诺。
public struct NuoSegmented<T: Hashable>: View {
    private let options: [(value: T, label: String, icon: String?)]
    private let selection: T
    private let onSelect: (T) -> Void
    @Namespace private var namespace

    public init(
        options: [(value: T, label: String, icon: String?)],
        selection: T,
        onSelect: @escaping (T) -> Void
    ) {
        self.options = options
        self.selection = selection
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button {
                    withAnimation(NuoCurve.snappy) { onSelect(option.value) }
                } label: {
                    HStack(spacing: NuoSpace.xs) {
                        if let icon = option.icon {
                            Image(systemName: icon)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text(option.label)
                            .nuoType(NuoType.captionStrong)
                    }
                    .foregroundStyle(isSelected ? NuoColor.textPrimary : NuoColor.textTertiary)
                    .padding(.horizontal, NuoSpace.sm)
                    .padding(.vertical, NuoSpace.xxs + 1)
                    .frame(maxWidth: .infinity)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: NuoRadius.chip, style: .continuous)
                                .fill(NuoColor.surfaceElevated)
                                .overlay {
                                    RoundedRectangle(cornerRadius: NuoRadius.chip, style: .continuous)
                                        .strokeBorder(NuoColor.separator, lineWidth: NuoStroke.hairline)
                                }
                                .matchedGeometryEffect(id: "nuoSegment", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: NuoRadius.chip + 1, style: .continuous)
                .fill(NuoColor.surfaceSunken)
        )
        .fixedSize()
    }
}

// MARK: - 状态点

/// 状态点。比光球轻，用于列表行与设置项。
///
/// 只允许四种色：朱（活动）、墨（空闲）、竹青（成功）、赭石（警告）。
public struct NuoStatusDot: View {
    private let color: Color
    private let size: CGFloat
    private let pulsing: Bool

    public init(color: Color = NuoPalette.cinnabar, size: CGFloat = 6, pulsing: Bool = false) {
        self.color = color
        self.size = size
        self.pulsing = pulsing
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                if pulsing {
                    Circle()
                        .stroke(color.opacity(0.35), lineWidth: 1)
                        .scaleEffect(2.1)
                        .opacity(0.6)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Chip

/// 标签。用于模型名、工具名、来源、模式。
public struct NuoChip: View {
    private let text: String
    private let icon: String?
    private let tint: Color
    private let interactive: Bool
    private let action: (() -> Void)?
    @State private var hovering = false

    public init(
        _ text: String,
        icon: String? = nil,
        tint: Color = NuoColor.textSecondary,
        interactive: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.text = text
        self.icon = icon
        self.tint = tint
        self.interactive = interactive
        self.action = action
    }

    public var body: some View {
        let content = HStack(spacing: NuoSpace.xxs + 1) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .nuoType(NuoType.caption)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, NuoSpace.xs)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: NuoRadius.chip, style: .continuous)
                .fill(hovering && interactive ? NuoColor.surfaceSunken : NuoColor.surface.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NuoRadius.chip, style: .continuous)
                .strokeBorder(NuoColor.separator, lineWidth: NuoStroke.hairline)
        )
        .contentShape(RoundedRectangle(cornerRadius: NuoRadius.chip, style: .continuous))
        .onHover { hovering = $0 }

        if interactive, let action {
            Button(action: action) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }
}
