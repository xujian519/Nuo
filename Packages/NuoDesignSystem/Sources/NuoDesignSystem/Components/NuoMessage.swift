//
//  NuoMessage.swift
//  NuoDesignSystem
//
//  对话内容的最小单元。
//
//  一个关键决策：**不做聊天气泡。**
//
//  气泡（左右对齐的圆角块）是即时通讯的语法，它暗示"这是两个人来回发消息"。
//  但智能体的回答是一份**文档**——可以长、可以有代码、可以有表格、可以被引用。
//  把它塞进一个 70% 宽的气泡里，是这套界面最容易犯的错，也是它和 Grok /
//  Claude 在观感上拉开差距的地方。
//
//  取而代之的三层结构：
//
//    1. 你的话 → 一张抬升的卡片（`nuoSurface`），左侧留一条朱红细线。
//       它被"收起来"了，因为它已经完成了它的使命。
//    2. 它的过程 → 一条可折叠的"脊"（`NuoActivitySpine`）。默认收起。
//       用户不关心，但需要它存在——这是可审计性的视觉表达。
//    3. 它的回答 → 直接长在画布上，没有任何容器。宽度锁在 680pt。
//       这一层是唯一没有"框"的东西，因为它就是内容本身。
//

import SwiftUI

// MARK: - 角色

public enum NuoRole: Sendable {
    case user
    case agent
    case system
}

// MARK: - 一条消息

public struct NuoMessageRow<Content: View>: View {
    private let role: NuoRole
    private let agentName: String
    private let presence: NuoPresenceState
    private let timestamp: String?
    private let showsHeader: Bool
    private let content: Content
    private let onCopy: (() -> Void)?
    private let onRetry: (() -> Void)?
    private let onRemember: (() -> Void)?

    @State private var hovering = false

    public init(
        role: NuoRole,
        agentName: String = "Nuo",
        presence: NuoPresenceState = .idle,
        timestamp: String? = nil,
        showsHeader: Bool = true,
        onCopy: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil,
        onRemember: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.role = role
        self.agentName = agentName
        self.presence = presence
        self.timestamp = timestamp
        self.showsHeader = showsHeader
        self.onCopy = onCopy
        self.onRetry = onRetry
        self.onRemember = onRemember
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NuoSpace.sm) {
            if showsHeader {
                header
            }

            switch role {
            case .user:
                userContent
            case .agent:
                agentContent
            case .system:
                systemContent
            }

            if hovering || role == .agent {
                actions
                    .opacity(hovering ? 1 : 0)
            }
        }
        .frame(maxWidth: NuoMetrics.readingColumn, alignment: .leading)
        .onHover { hovering = $0 }
        .animation(NuoCurve.quick, value: hovering)
        .transition(.nuoMessage)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(role == .user ? "你说" : agentName))
    }

    // MARK: 头

    private var header: some View {
        HStack(spacing: NuoSpace.sm) {
            switch role {
            case .agent:
                PresenceOrb(state: presence, diameter: 16)
                Text(agentName)
                    .nuoType(NuoType.captionStrong)
                    .foregroundStyle(NuoColor.textSecondary)
            case .user:
                Text("你")
                    .nuoType(NuoType.captionStrong)
                    .foregroundStyle(NuoColor.textTertiary)
            case .system:
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(NuoColor.textTertiary)
                Text("系统")
                    .nuoType(NuoType.captionStrong)
                    .foregroundStyle(NuoColor.textTertiary)
            }

            if let timestamp {
                Text(timestamp)
                    .nuoType(NuoType.caption)
                    .foregroundStyle(NuoColor.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 三种内容形态

    private var userContent: some View {
        content
            .nuoType(NuoType.body)
            .foregroundStyle(NuoColor.textPrimary)
            .padding(.horizontal, NuoSpace.md + 2)
            .padding(.vertical, NuoSpace.sm + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: NuoRadius.card, style: .continuous)
                    .fill(NuoColor.surface)
            )
            .overlay(alignment: .leading) {
                // 一条 2pt 的朱红细线。这是"人说的话"的唯一标记，
                // 比头像更安静，也比气泡更省空间。
                UnevenRoundedRectangle(
                    topLeadingRadius: NuoRadius.card,
                    bottomLeadingRadius: NuoRadius.card,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(NuoColor.accent.opacity(0.55))
                .frame(width: 2)
            }
            .overlay(
                RoundedRectangle(cornerRadius: NuoRadius.card, style: .continuous)
                    .strokeBorder(NuoColor.separator, lineWidth: NuoStroke.hairline)
            )
    }

    private var agentContent: some View {
        content
            .nuoType(NuoType.body)
            .foregroundStyle(NuoColor.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, NuoSpace.lg + NuoSpace.xxs)  // 与头部的光球对齐
    }

    private var systemContent: some View {
        content
            .nuoType(NuoType.callout)
            .foregroundStyle(NuoColor.textSecondary)
            .padding(.horizontal, NuoSpace.md)
            .padding(.vertical, NuoSpace.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: NuoRadius.chip, style: .continuous)
                    .fill(NuoColor.surfaceSunken)
            )
    }

    // MARK: 悬停操作

    private var actions: some View {
        HStack(spacing: NuoSpace.xxs) {
            if let onCopy {
                NuoIconButton(systemName: "doc.on.doc", help: "复制", size: 22, action: onCopy)
            }
            if let onRetry, role == .agent {
                NuoIconButton(systemName: "arrow.clockwise", help: "重新生成", size: 22, action: onRetry)
            }
            if let onRemember, role == .agent {
                NuoIconButton(systemName: "bookmark", help: "存入记忆", size: 22, action: onRemember)
            }
        }
        .padding(.leading, role == .agent ? NuoSpace.lg + NuoSpace.xxs : 0)
    }
}

// MARK: - 过程脊

/// 过程脊：工具调用与思考步骤的折叠容器。
///
/// 三个设计取舍：
/// 1. **默认收起**。大多数时候用户只想要答案；展开动作本身代表"我在审计你"。
/// 2. **收起时仍然显示步数与耗时**。这是"我没有偷偷做事"的最小证据。
/// 3. **不用卡片包起来**。用一条 1px 竖线串起节点，重量最轻。
public struct NuoActivitySpine<Step: View>: View {
    private let summary: String
    private let durationText: String?
    private let hasFailure: Bool
    private let isExpanded: Bool
    private let onToggle: () -> Void
    private let steps: Step

    public init(
        summary: String,
        durationText: String? = nil,
        hasFailure: Bool = false,
        isExpanded: Bool,
        onToggle: @escaping () -> Void,
        @ViewBuilder steps: () -> Step
    ) {
        self.summary = summary
        self.durationText = durationText
        self.hasFailure = hasFailure
        self.isExpanded = isExpanded
        self.onToggle = onToggle
        self.steps = steps()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NuoSpace.sm) {
            Button(action: onToggle) {
                HStack(spacing: NuoSpace.xs) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(NuoColor.textTertiary)
                        .frame(width: 10)

                    Text(summary)
                        .nuoType(NuoType.caption)
                        .foregroundStyle(NuoColor.textSecondary)

                    if let durationText {
                        Text("·")
                            .nuoType(NuoType.caption)
                            .foregroundStyle(NuoColor.textTertiary)
                        Text(durationText)
                            .nuoType(NuoType.caption)
                            .monospacedDigit()
                            .foregroundStyle(NuoColor.textTertiary)
                    }

                    if hasFailure {
                        NuoStatusDot(color: NuoColor.danger, size: 5)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                HStack(alignment: .top, spacing: NuoSpace.sm) {
                    // 竖脊：从第一个节点延伸到最后。
                    Rectangle()
                        .fill(NuoColor.separator)
                        .frame(width: 1)
                        .padding(.leading, 4.5)
                    VStack(alignment: .leading, spacing: NuoSpace.xs) {
                        steps
                    }
                }
                .padding(.leading, NuoSpace.lg)
                .transition(.nuoMessage)
            }
        }
        .animation(NuoCurve.panel, value: isExpanded)
    }
}

// MARK: - 一个步骤

public enum NuoStepStatus: Sendable {
    case pending
    case running
    case done
    case failed(String?)

    var icon: String {
        switch self {
        case .pending: return "circle"
        case .running: return "circle.dotted"
        case .done: return "checkmark"
        case .failed: return "exclamationmark"
        }
    }

    var color: Color {
        switch self {
        case .pending: return NuoColor.textTertiary
        case .running: return NuoColor.accent
        case .done: return NuoColor.textTertiary
        case .failed: return NuoColor.danger
        }
    }
}

public struct NuoActivityStep: View {
    private let title: String
    private let detail: String?
    private let status: NuoStepStatus
    private let durationText: String?

    public init(title: String, detail: String? = nil, status: NuoStepStatus = .done, durationText: String? = nil) {
        self.title = title
        self.detail = detail
        self.status = status
        self.durationText = durationText
    }

    public var body: some View {
        HStack(alignment: .top, spacing: NuoSpace.sm) {
            // 节点：盖在脊线上的小圆点。
            ZStack {
                Circle()
                    .fill(NuoPalette.paper)
                    .frame(width: 9, height: 9)
                Image(systemName: status.icon)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(status.color)
            }
            .offset(x: -4.5)
            .frame(width: 9)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: NuoSpace.xs) {
                    Text(title)
                        .nuoType(NuoType.callout)
                        .foregroundStyle(NuoColor.textPrimary)
                    if let durationText {
                        Text(durationText)
                            .nuoType(NuoType.caption)
                            .monospacedDigit()
                            .foregroundStyle(NuoColor.textTertiary)
                    }
                }
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .nuoType(NuoType.caption)
                        .foregroundStyle(NuoColor.textTertiary)
                        .lineLimit(2)
                }
                if case .failed(let message) = status, let message {
                    Text(message)
                        .nuoType(NuoType.caption)
                        .foregroundStyle(NuoColor.danger)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 思考块

/// 模型的推理过程。默认收起，展开后用衬线——它是"独白"，不是"结论"。
public struct NuoReasoningBlock: View {
    private let text: String
    private let isExpanded: Bool
    private let onToggle: () -> Void

    public init(text: String, isExpanded: Bool, onToggle: @escaping () -> Void) {
        self.text = text
        self.isExpanded = isExpanded
        self.onToggle = onToggle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NuoSpace.xs) {
            Button(action: onToggle) {
                HStack(spacing: NuoSpace.xs) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                    Text("想")
                        .font(.system(size: 10, weight: .semibold, design: .serif))
                    Text(isExpanded ? "收起思路" : "看它怎么想的")
                        .nuoType(NuoType.caption)
                }
                .foregroundStyle(NuoColor.textTertiary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(text)
                    .font(.system(size: 13, design: .serif))
                    .lineSpacing(5)
                    .foregroundStyle(NuoColor.textSecondary)
                    .padding(.leading, NuoSpace.md)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(NuoColor.separator)
                            .frame(width: 1)
                    }
            }
        }
    }
}

// MARK: - 代码块

/// 代码块。只做两件事：等宽 + 可复制。
/// 高亮限制在两色（关键字 / 字符串），因为五行彩色高亮会破坏整页的纸感。
public struct NuoCodeBlock: View {
    private let code: String
    private let language: String?
    @State private var copied = false

    public init(_ code: String, language: String? = nil) {
        self.code = code
        self.language = language
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: NuoSpace.xs) {
                if let language {
                    Text(language)
                        .nuoType(NuoType.caption)
                        .foregroundStyle(NuoColor.textTertiary)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 8, weight: .semibold))
                        Text(copied ? "已复制" : "复制")
                            .nuoType(NuoType.caption)
                    }
                    .foregroundStyle(copied ? NuoColor.success : NuoColor.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, NuoSpace.md)
            .padding(.vertical, NuoSpace.xs)

            NuoHairline(color: NuoPalette.codeBorder)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .nuoType(NuoType.code)
                    .foregroundStyle(NuoColor.textPrimary)
                    .textSelection(.enabled)
                    .padding(NuoSpace.md)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: NuoRadius.card, style: .continuous)
                .fill(NuoPalette.codeBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NuoRadius.card, style: .continuous)
                .strokeBorder(NuoPalette.codeBorder, lineWidth: NuoStroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: NuoRadius.card, style: .continuous))
    }
}

// MARK: - 来源

/// 来源标签。所有引用都必须能点回原文——这是本地智能体最重要的信任细节。
public struct NuoSourcePill: View {
    private let name: String
    private let line: Int?
    private let action: (() -> Void)?

    public init(name: String, line: Int? = nil, action: (() -> Void)? = nil) {
        self.name = name
        self.line = line
        self.action = action
    }

    public var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "doc.text")
                    .font(.system(size: 8, weight: .medium))
                Text(name)
                    .nuoType(NuoType.caption)
                    .lineLimit(1)
                if let line {
                    Text(":\(line)")
                        .nuoType(NuoType.caption)
                        .monospacedDigit()
                        .foregroundStyle(NuoColor.accent)
                }
            }
            .foregroundStyle(NuoColor.textSecondary)
            .padding(.horizontal, NuoSpace.xs)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: NuoRadius.chip, style: .continuous)
                    .fill(NuoColor.surfaceSunken)
            )
        }
        .buttonStyle(.plain)
        .help("打开来源")
    }
}

// MARK: - 光标

/// 流式输出时的光标。
///
/// 用 2pt 宽的竖条 + 呼吸，而不是"▍"字符——字符会占一个字的宽度，
/// 导致文字在生成过程中跳行。
public struct NuoStreamingCaret: View {
    @State private var visible = true

    public init() {}

    public var body: some View {
        Rectangle()
            .fill(NuoColor.accent)
            .frame(width: 2, height: 15)
            .opacity(visible ? 1 : 0.15)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - 追问建议

/// 回答之后的追问建议。最多三条，超过就变成噪音。
public struct NuoFollowUps: View {
    private let suggestions: [String]
    private let onSelect: (String) -> Void

    public init(suggestions: [String], onSelect: @escaping (String) -> Void) {
        self.suggestions = Array(suggestions.prefix(3))
        self.onSelect = onSelect
    }

    public var body: some View {
        FlowRow(spacing: NuoSpace.xs) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    onSelect(suggestion)
                } label: {
                    Text(suggestion)
                        .nuoType(NuoType.caption)
                        .foregroundStyle(NuoColor.textSecondary)
                        .padding(.horizontal, NuoSpace.sm)
                        .padding(.vertical, NuoSpace.xxs + 1)
                        .background(
                            Capsule()
                                .fill(NuoColor.surface)
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(NuoColor.separator, lineWidth: NuoStroke.hairline)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - 简易流式换行布局

/// 一个不依赖 Layout 协议的简单 flow 布局。
/// 用 `Layout` 协议会更优雅，但这里只需要横向换行，
/// 保持文件自包含、可单独拷进主工程。
struct FlowRow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
