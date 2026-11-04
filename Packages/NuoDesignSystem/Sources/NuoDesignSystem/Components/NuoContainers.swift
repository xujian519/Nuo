//
//  NuoContainers.swift
//  NuoDesignSystem
//
//  容器类组件：卡片、空状态、设置行、命令面板、浮层提示。
//
//  这一层的共同约束是**信息密度**：每一屏只允许有一个"主标题级"元素，
//  其余全部降为 13pt / 11.5pt。当所有东西都在喊的时候，就没人被听见。
//

import SwiftUI

// MARK: - 卡片

/// 基础卡片。
///
/// 卡片**不是**用来"装东西"的默认选择。它只用于：
/// · 一组需要在视觉上被认作整体的信息（一个智能体的配置摘要）；
/// · 可以被单独移除/拖动的对象（附件、插件）。
/// 平铺的列表项、设置项不用卡片，用发丝线分隔即可。
public struct NuoCard<Content: View>: View {
    private let title: String?
    private let subtitle: String?
    private let icon: String?
    private let content: Content
    private let action: (() -> Void)?

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        icon: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.action = action
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NuoSpace.sm) {
            if title != nil || icon != nil {
                HStack(spacing: NuoSpace.xs) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(NuoColor.textSecondary)
                            .frame(width: 14)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        if let title {
                            Text(title)
                                .nuoType(NuoType.headline)
                                .foregroundStyle(NuoColor.textPrimary)
                        }
                        if let subtitle {
                            Text(subtitle)
                                .nuoType(NuoType.caption)
                                .foregroundStyle(NuoColor.textTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                    if let action {
                        NuoButton(role: .ghost, compact: true, action: action) {
                            Text("打开")
                        }
                    }
                }
            }
            content
        }
        .padding(NuoSpace.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nuoSurface()
    }
}

// MARK: - 空状态

/// 空状态。
///
/// 三条规矩：
/// 1. 只有一句话，不超过 14 个字。解释性文字放第二行，11.5pt，灰。
/// 2. 水印印章降到 12% —— 它是纸上的旧印，不是新盖的。
/// 3. 最多一个操作按钮。空状态不是导航页。
public struct NuoEmptyState: View {
    private let title: String
    private let message: String?
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(
        title: String,
        message: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: NuoSpace.md) {
            NuoSealMark(style: .watermark, size: NuoMetrics.sealLarge)
                .opacity(0.55)
                .padding(.bottom, NuoSpace.xs)

            Text(title)
                .nuoType(NuoType.taglineSerif)
                .foregroundStyle(NuoColor.textSecondary)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .nuoType(NuoType.callout)
                    .foregroundStyle(NuoColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            if let actionTitle, let action {
                NuoButton(role: .secondary, action: action) {
                    Text(actionTitle)
                }
                .padding(.top, NuoSpace.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NuoSpace.breathing)
    }
}

// MARK: - 设置行

/// 设置行。左标签 + 右控件，说明文字在标签下方。
///
/// 不使用 macOS 的 `Form`，因为它会引入系统灰底与控件内边距，
/// 和这套纸面体系冲突；自己排 28pt 行高反而更紧凑、更一致。
public struct NuoSettingRow<Trailing: View>: View {
    private let title: String
    private let detail: String?
    private let trailing: Trailing

    public init(
        title: String,
        detail: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: NuoSpace.lg) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .nuoType(NuoType.body)
                    .foregroundStyle(NuoColor.textPrimary)
                if let detail {
                    Text(detail)
                        .nuoType(NuoType.caption)
                        .foregroundStyle(NuoColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: NuoSpace.md)
            trailing
        }
        .padding(.vertical, NuoSpace.sm)
        .frame(minHeight: 36)
    }
}

// MARK: - 输入字段

public struct NuoField: View {
    private let label: String
    private let help: String?
    @Binding private var text: String
    private let placeholder: String

    public init(
        _ label: String,
        text: Binding<String>,
        placeholder: String = "",
        help: String? = nil
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.help = help
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NuoSpace.xs) {
            Text(label)
                .nuoType(NuoType.captionStrong)
                .foregroundStyle(NuoColor.textSecondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .nuoType(NuoType.body)
                .padding(.horizontal, NuoSpace.sm)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: NuoRadius.control, style: .continuous)
                        .fill(NuoColor.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: NuoRadius.control, style: .continuous)
                        .strokeBorder(NuoColor.separator, lineWidth: NuoStroke.hairline)
                )
            if let help {
                Text(help)
                    .nuoType(NuoType.caption)
                    .foregroundStyle(NuoColor.textTertiary)
            }
        }
    }
}

// MARK: - 命令面板

/// ⌘K 命令面板。
///
/// 智能体应用必须有一个"跳"的入口：跳到某个会话、某个智能体、某个工具、
/// 某个记忆。否则一旦对话超过 200 条，侧栏就变成了考古现场。
public struct NuoCommandItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let category: String
    public let icon: String
    public let shortcut: String?

    public init(
        id: UUID = UUID(),
        title: String,
        category: String,
        icon: String,
        shortcut: String? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.icon = icon
        self.shortcut = shortcut
    }
}

public struct NuoCommandPalette: View {
    @Binding private var query: String
    private let items: [NuoCommandItem]
    private let onRun: (NuoCommandItem) -> Void
    @FocusState private var focused: Bool

    public init(
        query: Binding<String>,
        items: [NuoCommandItem],
        onRun: @escaping (NuoCommandItem) -> Void
    ) {
        self._query = query
        self.items = items
        self.onRun = onRun
    }

    private var filtered: [NuoCommandItem] {
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.category.localizedCaseInsensitiveContains(query)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: NuoSpace.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NuoColor.textTertiary)
                TextField("跳到哪里，或者做什么", text: $query)
                    .textFieldStyle(.plain)
                    .nuoType(NuoType.body)
                    .focused($focused)
                Text("esc")
                    .nuoType(NuoType.caption)
                    .foregroundStyle(NuoColor.textTertiary)
            }
            .padding(.horizontal, NuoSpace.md)
            .frame(height: 44)

            NuoHairline()

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(filtered) { item in
                        Button {
                            onRun(item)
                        } label: {
                            HStack(spacing: NuoSpace.sm) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(NuoColor.textTertiary)
                                    .frame(width: 14)
                                Text(item.title)
                                    .nuoType(NuoType.body)
                                    .foregroundStyle(NuoColor.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: NuoSpace.sm)
                                Text(item.category)
                                    .nuoType(NuoType.caption)
                                    .foregroundStyle(NuoColor.textTertiary)
                                if let shortcut = item.shortcut {
                                    Text(shortcut)
                                        .nuoType(NuoType.caption)
                                        .foregroundStyle(NuoColor.textTertiary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(NuoColor.surfaceSunken)
                                        )
                                }
                            }
                            .padding(.horizontal, NuoSpace.md)
                            .frame(height: 32)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, NuoSpace.xs)
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 520)
        .nuoFloat(radius: NuoRadius.sheet, level: .high)
        .onAppear { focused = true }
    }
}

// MARK: - 浮层提示

/// 底部浮出的提示。
///
/// 位置刻意放在 dock 上方 12pt 而不是窗口底部——它属于**输入区**的语境，
/// 不属于整个窗口。
public struct NuoToast: View {
    public enum Kind {
        case info, success, failure

        var icon: String {
            switch self {
            case .info: return "info.circle"
            case .success: return "checkmark.circle"
            case .failure: return "exclamationmark.circle"
            }
        }

        var color: Color {
            switch self {
            case .info: return NuoColor.textSecondary
            case .success: return NuoColor.success
            case .failure: return NuoColor.danger
            }
        }
    }

    private let kind: Kind
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(kind: Kind = .info, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.kind = kind
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(spacing: NuoSpace.sm) {
            Image(systemName: kind.icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(kind.color)
            Text(message)
                .nuoType(NuoType.callout)
                .foregroundStyle(NuoColor.textPrimary)
                .lineLimit(2)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .nuoType(NuoType.captionStrong)
                        .foregroundStyle(NuoColor.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, NuoSpace.md)
        .padding(.vertical, NuoSpace.sm)
        .nuoFloat(radius: NuoRadius.capsule, level: .mid)
        .frame(maxWidth: 420)
    }
}

// MARK: - Sheet 头

public struct NuoSheetHeader: View {
    private let title: String
    private let subtitle: String?
    private let onClose: () -> Void

    public init(title: String, subtitle: String? = nil, onClose: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
    }

    public var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .nuoType(NuoType.title2)
                    .foregroundStyle(NuoColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .nuoType(NuoType.callout)
                        .foregroundStyle(NuoColor.textTertiary)
                }
            }
            Spacer(minLength: NuoSpace.md)
            NuoIconButton(systemName: "xmark", help: "关闭 (esc)", size: 24, action: onClose)
        }
        .padding(.horizontal, NuoSpace.xxl)
        .padding(.top, NuoSpace.xl)
        .padding(.bottom, NuoSpace.md)
        .overlay(alignment: .bottom) { NuoHairline() }
    }
}

// MARK: - 授权卡

/// 授权请求。
///
/// 这是整个产品里**最重**的一个组件。它出现在智能体要动用户东西的时候。
///
/// 设计上的三个决定：
/// 1. 不用系统 Alert。系统 Alert 会被习惯性连点掉，而这里需要被读。
/// 2. 把"将发生什么"写成一句人话（`effect`），不写代码路径。
/// 3. 「允许一次」是主按钮，「总是允许」是次按钮 —— 默认值必须是**最小授权**。
public struct NuoConsentCard: View {
    private let title: String
    private let effect: String
    private let detail: String?
    private let onAllowOnce: () -> Void
    private let onAllowAlways: () -> Void
    private let onDeny: () -> Void

    public init(
        title: String,
        effect: String,
        detail: String? = nil,
        onAllowOnce: @escaping () -> Void,
        onAllowAlways: @escaping () -> Void,
        onDeny: @escaping () -> Void
    ) {
        self.title = title
        self.effect = effect
        self.detail = detail
        self.onAllowOnce = onAllowOnce
        self.onAllowAlways = onAllowAlways
        self.onDeny = onDeny
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NuoSpace.md) {
            HStack(spacing: NuoSpace.sm) {
                NuoSealMark(style: .outline, size: 18)
                Text(title)
                    .nuoType(NuoType.headline)
                    .foregroundStyle(NuoColor.textPrimary)
            }

            Text(effect)
                .nuoType(NuoType.body)
                .foregroundStyle(NuoColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let detail {
                Text(detail)
                    .nuoType(NuoType.mono)
                    .foregroundStyle(NuoColor.textSecondary)
                    .padding(NuoSpace.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: NuoRadius.chip, style: .continuous)
                            .fill(NuoColor.surfaceSunken)
                    )
            }

            HStack(spacing: NuoSpace.sm) {
                NuoButton(role: .primary, action: onAllowOnce) {
                    Text("允许一次")
                }
                NuoButton(role: .secondary, action: onAllowAlways) {
                    Text("总是允许")
                }
                Spacer(minLength: 0)
                NuoButton(role: .ghost, action: onDeny) {
                    Text("不")
                }
            }
        }
        .padding(NuoSpace.lg)
        .nuoFloat(radius: NuoRadius.sheet, level: .high)
    }
}
