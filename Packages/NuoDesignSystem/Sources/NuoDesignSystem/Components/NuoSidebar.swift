//
//  NuoSidebar.swift
//  NuoDesignSystem
//
//  左侧会话侧栏。
//
//  侧栏的职责是"让人相信东西都还在"。它不该抢戏，所以：
//
//  · 底用 `paperSunken`（比画布低一层），靠明度差而不是分隔线把它推远。
//  · 行高 30pt，比 macOS 标准的 24 高——中文标题需要喘息，也给触达留余地。
//  · 选中态**不用朱红填充**，用抬升面 + 左侧 2pt 朱红线。朱红一铺开就不值钱了。
//  · 每个分区最多显示 8 条，超出用"更多"，避免滚动条变成"历史垃圾场"。
//  · 运行中的会话在行尾显示极小的光球，而不是转圈——转圈是"加载"，光球是"它活着"。
//
//  宽度：260pt（`NuoMetrics.sidebarWidth`）。窗口窄于 880pt 自动折叠（⌘B 手动）。
//

import SwiftUI

// MARK: - 数据

public struct NuoSessionItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let subtitle: String?
    /// 右侧时间，如 "14:02" / "昨天"。
    public let timeText: String?
    /// 该会话的智能体是否正在跑。
    public let isRunning: Bool
    /// 是否有未读。
    public let isUnread: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        timeText: String? = nil,
        isRunning: Bool = false,
        isUnread: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.timeText = timeText
        self.isRunning = isRunning
        self.isUnread = isUnread
    }
}

public struct NuoSessionSection: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let items: [NuoSessionItem]

    public init(id: UUID = UUID(), title: String, items: [NuoSessionItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

// MARK: - 侧栏

public struct NuoSidebar: View {
    private let agentName: String
    private let presence: NuoPresenceState
    private let sections: [NuoSessionSection]
    @Binding private var selectedID: UUID?
    @Binding private var searchText: String
    private let modelName: String
    private let onNewChat: () -> Void
    private let onSelect: (NuoSessionItem) -> Void
    private let onSettings: () -> Void
    private let onSwitchAgent: () -> Void

    public init(
        agentName: String = "诺",
        presence: NuoPresenceState = .idle,
        sections: [NuoSessionSection],
        selectedID: Binding<UUID?>,
        searchText: Binding<String>,
        modelName: String = "本机 · Raptor 0.6",
        onNewChat: @escaping () -> Void,
        onSelect: @escaping (NuoSessionItem) -> Void,
        onSettings: @escaping () -> Void,
        onSwitchAgent: @escaping () -> Void
    ) {
        self.agentName = agentName
        self.presence = presence
        self.sections = sections
        self._selectedID = selectedID
        self._searchText = searchText
        self.modelName = modelName
        self.onNewChat = onNewChat
        self.onSelect = onSelect
        self.onSettings = onSettings
        self.onSwitchAgent = onSwitchAgent
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, NuoSpace.sm)
                .padding(.top, NuoSpace.sm)
                .padding(.bottom, NuoSpace.xs)

            searchField
                .padding(.horizontal, NuoSpace.sm)
                .padding(.bottom, NuoSpace.xs)

            newChatButton
                .padding(.horizontal, NuoSpace.sm)
                .padding(.bottom, NuoSpace.sm)

            NuoHairline()
                .padding(.horizontal, NuoSpace.sm)
                .padding(.bottom, NuoSpace.xs)

            sessionList

            footer
        }
        .frame(width: NuoMetrics.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(NuoColor.surfaceSunken)
        .overlay(alignment: .trailing) {
            NuoHairline(vertical: true)
        }
    }

    // MARK: 头

    private var header: some View {
        HStack {
            NuoIdentityBadge(agentName: agentName, state: presence, onTap: onSwitchAgent)
            Spacer(minLength: 0)
            NuoIconButton(systemName: "square.on.square", help: "新建窗口 (⇧⌘N)", size: 22) {}
        }
    }

    // MARK: 搜索

    private var searchField: some View {
        HStack(spacing: NuoSpace.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NuoColor.textTertiary)
            TextField("搜索对话", text: $searchText)
                .textFieldStyle(.plain)
                .nuoType(NuoType.callout)
                .foregroundStyle(NuoColor.textPrimary)
            Text("⌘K")
                .nuoType(NuoType.caption)
                .foregroundStyle(NuoColor.textTertiary)
        }
        .padding(.horizontal, NuoSpace.sm)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: NuoRadius.chip, style: .continuous)
                .fill(NuoColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NuoRadius.chip, style: .continuous)
                .strokeBorder(NuoColor.separator, lineWidth: NuoStroke.hairline)
        )
    }

    // MARK: 新对话

    private var newChatButton: some View {
        NuoButton(role: .primary, fullWidth: true, action: onNewChat) {
            HStack(spacing: NuoSpace.xs) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                Text("新对话")
                Spacer(minLength: 0)
                Text("⌘N")
                    .nuoType(NuoType.caption)
                    .opacity(0.6)
            }
        }
    }

    // MARK: 列表

    private var sessionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: NuoSpace.sm + 2) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 2) {
                        NuoSectionHeader(title: section.title, count: section.items.count)
                            .padding(.horizontal, NuoSpace.sm + NuoSpace.xxs)
                        ForEach(section.items) { item in
                            NuoSessionRow(
                                item: item,
                                isSelected: item.id == selectedID
                            ) {
                                selectedID = item.id
                                onSelect(item)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, NuoSpace.xs)
            .padding(.bottom, NuoSpace.lg)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: 脚

    private var footer: some View {
        VStack(spacing: 0) {
            NuoHairline()
            HStack(spacing: NuoSpace.xs) {
                NuoStatusDot(color: NuoPalette.success, size: 5)
                Text(modelName)
                    .nuoType(NuoType.caption)
                    .foregroundStyle(NuoColor.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                NuoIconButton(systemName: "gearshape", help: "设置 (⌘,)", size: 22, action: onSettings)
            }
            .padding(.horizontal, NuoSpace.sm + NuoSpace.xxs)
            .padding(.vertical, NuoSpace.xs)
        }
    }
}

// MARK: - 分区头

public struct NuoSectionHeader: View {
    private let title: String
    private let count: Int?

    public init(title: String, count: Int? = nil) {
        self.title = title
        self.count = count
    }

    public var body: some View {
        HStack(spacing: NuoSpace.xs) {
            Text(title)
                .nuoType(NuoType.captionStrong)
                .foregroundStyle(NuoColor.textTertiary)
            if let count, count > 0 {
                Text("\(count)")
                    .nuoType(NuoType.caption)
                    .monospacedDigit()
                    .foregroundStyle(NuoColor.textTertiary.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, NuoSpace.xs)
        .padding(.bottom, 1)
    }
}

// MARK: - 会话行

public struct NuoSessionRow: View {
    private let item: NuoSessionItem
    private let isSelected: Bool
    private let action: () -> Void

    @State private var hovering = false

    public init(item: NuoSessionItem, isSelected: Bool, action: @escaping () -> Void) {
        self.item = item
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: NuoSpace.xs) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title)
                        .nuoType(NuoType.callout)
                        .fontWeight(isSelected ? .medium : .regular)
                        .foregroundStyle(isSelected ? NuoColor.textPrimary : NuoColor.textSecondary)
                        .lineLimit(1)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .nuoType(NuoType.caption)
                            .foregroundStyle(NuoColor.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: NuoSpace.xxs)

                // 右侧：优先级 running > time > unread 点
                if item.isRunning {
                    PresenceOrb(state: .thinking, diameter: 10)
                } else if hovering {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NuoColor.textTertiary)
                } else if let time = item.timeText {
                    Text(time)
                        .nuoType(NuoType.caption)
                        .foregroundStyle(NuoColor.textTertiary)
                } else if item.isUnread {
                    NuoStatusDot(color: NuoColor.accent, size: 5)
                }
            }
            .padding(.horizontal, NuoMetrics.sessionRowInset)
            .frame(height: item.subtitle == nil ? NuoMetrics.sessionRowHeight : NuoMetrics.sessionRowHeight + 12)
            .background(
                RoundedRectangle(cornerRadius: NuoRadius.chip, style: .continuous)
                    .fill(
                        isSelected
                            ? NuoColor.surface
                            : (hovering ? NuoColor.surface.opacity(0.6) : Color.clear)
                    )
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    // 选中标识：2pt 朱红竖线。整行只有这一个彩色像素列。
                    UnevenRoundedRectangle(
                        topLeadingRadius: NuoRadius.chip,
                        bottomLeadingRadius: NuoRadius.chip,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                    .fill(NuoColor.accent)
                    .frame(width: 2)
                    .padding(.vertical, 6)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: NuoRadius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(NuoCurve.quick, value: hovering)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
