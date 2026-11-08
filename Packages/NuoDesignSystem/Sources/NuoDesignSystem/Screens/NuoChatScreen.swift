//
//  NuoChatScreen.swift
//  NuoDesignSystem
//
//  主对话屏 —— 整套界的旗舰。
//
//  布局（横）：
//    侧栏 260 | 分隔 | 对话区（自适应）| 检查器 320（≥1180pt 才出现）
//
//  布局（纵）：
//    自绘标题栏 38 → 消息流（可滚，底部留出 dock 的高度）→ 浮动 dock
//
//  三个必须做对的细节：
//
//  1. **标题栏是自绘的**。系统 titlebar 已隐藏（`.fullSizeContentView`），
//     所以我们自己画红绿灯——但**静止时是三个墨点**，鼠标移到标题栏左侧
//     才浮现出红黄绿。这样窗口的"仪器感"被压到最低，而习惯没有被打断。
//  2. **dock 浮在内容之上**，不是压在底部的一个固定块。消息滚到它下面时会
//     被一层渐隐遮罩软化，暗示"还有内容在下面"。
//  3. **消息栏宽 680pt 且居中偏左**。不要水平居中——居中的长文在宽窗口里
//     会像 PPT。左对齐到 72pt 的装订线更稳。
//

import SwiftUI

// MARK: - 红绿灯

/// 自绘红绿灯。静止为墨点，悬停浮现系统色。
public struct NuoTrafficLights: View {
    private let onClose: () -> Void
    private let onMinimize: () -> Void
    private let onZoom: () -> Void
    @State private var hovering = false

    public init(
        onClose: @escaping () -> Void = {},
        onMinimize: @escaping () -> Void = {},
        onZoom: @escaping () -> Void = {}
    ) {
        self.onClose = onClose
        self.onMinimize = onMinimize
        self.onZoom = onZoom
    }

    public var body: some View {
        HStack(spacing: NuoMetrics.trafficLightGap) {
            light(color: Color(red: 0.93, green: 0.42, blue: 0.35), help: "关闭", action: onClose)
            light(color: Color(red: 0.95, green: 0.74, blue: 0.28), help: "最小化", action: onMinimize)
            light(color: Color(red: 0.36, green: 0.76, blue: 0.34), help: "缩放", action: onZoom)
        }
        .onHover { hovering = $0 }
        .animation(NuoCurve.quick, value: hovering)
    }

    private func light(color: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(hovering ? color : NuoPalette.ink.opacity(0.20))
                .frame(width: NuoMetrics.trafficLight, height: NuoMetrics.trafficLight)
                .overlay(
                    Circle().strokeBorder(
                        NuoPalette.ink.opacity(hovering ? 0.16 : 0.0),
                        lineWidth: 0.5
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(help))
    }
}

// MARK: - 标题栏

public struct NuoTitlebar<Trailing: View>: View {
    private let agentName: String
    private let presence: NuoPresenceState
    private let title: String?
    private let trailing: Trailing
    private let onClose: () -> Void

    public init(
        agentName: String,
        presence: NuoPresenceState,
        title: String? = nil,
        onClose: @escaping () -> Void = {},
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.agentName = agentName
        self.presence = presence
        self.title = title
        self.onClose = onClose
        self.trailing = trailing()
    }

    public var body: some View {
        ZStack {
            HStack {
                NuoTrafficLights(onClose: onClose)
                    .padding(.leading, NuoMetrics.trafficLightInset)
                Spacer()
                trailing
                    .padding(.trailing, NuoSpace.md)
            }

            // 中间：当前会话标题。它必须能被拖拽移动窗口。
            HStack(spacing: NuoSpace.xs) {
                if let title {
                    Text(title)
                        .nuoType(NuoType.caption)
                        .foregroundStyle(NuoColor.textTertiary)
                        .lineLimit(1)
                        .frame(maxWidth: 380)
                }
            }
            .allowsHitTesting(false)
        }
        .frame(height: NuoMetrics.titlebarHeight)
        .frame(maxWidth: .infinity)
        .background(NuoColor.canvas.opacity(0.001))  // 供 onTapGesture / 拖拽命中
    }
}

// MARK: - 主对话屏

/// 完整的主对话屏。可直接拷进工程作为视图骨架替换目标。
public struct NuoChatScreen: View {
    @State private var sidebarVisible = true
    @State private var composerText = ""
    @State private var mode: NuoComposerMode = .converse
    @State private var searchText = ""
    @State private var selectedSession: UUID?
    @State private var expandedActivity = false
    @State private var presence: NuoPresenceState = .idle

    private let demo: Bool

    /// - Parameter demo: true 时填入一套演示数据，便于预览与截图。
    public init(demo: Bool = true) {
        self.demo = demo
    }

    public var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                NuoSidebar(
                    agentName: "诺",
                    presence: presence,
                    sections: demo ? Self.demoSections : [],
                    selectedID: $selectedSession,
                    searchText: $searchText,
                    onNewChat: {},
                    onSelect: { _ in },
                    onSettings: {},
                    onSwitchAgent: {}
                )
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            conversation
        }
        .background(NuoColor.canvas)
        .overlay {
            // 纸纤维：铺在最上层，不参与命中测试。强度 0.10 已经够——
            // 它应该只在斜看屏幕时被察觉。
            NuoPaperGrain(intensity: 0.10)
                .opacity(0.75)
                .ignoresSafeArea()
        }
        .animation(NuoCurve.panel, value: sidebarVisible)
    }

    // MARK: 对话区

    private var conversation: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                NuoTitlebar(agentName: "诺", presence: presence, title: "Nuo 该怎么做 UI") {
                    HStack(spacing: NuoSpace.xxs) {
                        NuoIconButton(systemName: "sidebar.left", help: "显示/隐藏侧栏 (⌘B)", size: 24) {
                            sidebarVisible.toggle()
                        }
                        NuoIconButton(systemName: "clock.arrow.circlepath", help: "历史", size: 24) {}
                        NuoIconButton(systemName: "info.circle", help: "检查器 (⌥⌘I)", size: 24) {}
                    }
                }

                NuoHairline()

                ScrollView {
                    VStack(alignment: .leading, spacing: NuoMetrics.messageSpacing) {
                        messages
                    }
                    .padding(.horizontal, NuoMetrics.threadPadding + NuoSpace.section)
                    .padding(.top, NuoSpace.xxl)
                    // 底部留白 = dock 高度 + 呼吸。
                    .padding(.bottom, 160)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }

            // 底部渐隐 + 浮动 dock
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [NuoColor.canvas.opacity(0), NuoColor.canvas, NuoColor.canvas],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 96)
                .allowsHitTesting(false)
            }

            VStack {
                Spacer(minLength: 0)
                NuoComposer(
                    text: $composerText,
                    mode: $mode,
                    attachments: demo ? [NuoAttachment(name: "DESIGN_SPEC.md")] : [],
                    modelName: "本机 · Raptor 0.6",
                    presence: presence,
                    isStreaming: false,
                    onSend: { send() }
                )
                .frame(maxWidth: NuoMetrics.composerWidth)
                .padding(.bottom, NuoMetrics.composerBottomInset)
            }
        }
    }

    // MARK: 消息

    @ViewBuilder
    private var messages: some View {
        if demo {
            NuoMessageRow(role: .user, timestamp: "14:02", showsHeader: true) {
                Text("帮我把 Nuo 的界面重做一版，要能对标 Grok bot，但不要做成那种黑底发光的科技感。纯 Swift。")
            }

            NuoMessageRow(
                role: .agent,
                agentName: "诺",
                presence: .thinking,
                timestamp: "14:02"
            ) {
                VStack(alignment: .leading, spacing: NuoSpace.md) {
                    NuoActivitySpine(
                        summary: "做了 4 件事",
                        durationText: "8.4s",
                        isExpanded: expandedActivity,
                        onToggle: { expandedActivity.toggle() }
                    ) {
                        VStack(alignment: .leading, spacing: NuoSpace.xs) {
                            NuoActivityStep(
                                title: "读了 12 个视图文件",
                                detail: "Views/Chat、Views/Theme",
                                status: .done,
                                durationText: "1.2s"
                            )
                            NuoActivityStep(
                                title: "提取现有设计令牌",
                                detail: "ThemeProtocol 的 38 个字段",
                                status: .done,
                                durationText: "0.9s"
                            )
                            NuoActivityStep(
                                title: "写了 NuoDesignSystem",
                                detail: "color / type / metrics / motion",
                                status: .done,
                                durationText: "5.8s"
                            )
                            NuoActivityStep(
                                title: "编译验证",
                                detail: "swift build — Build complete",
                                status: .done,
                                durationText: "0.5s"
                            )
                        }
                    }

                    Text("界面改用「纸 + 印」这一族语言：底色是暖灰的宣纸，唯一的彩色是印泥朱红，且只出现在两处——**它活着**和**你按下发送**。")
                        .nuoType(NuoType.body)

                    Text("这样做的好处是，界面上任何一个红色的像素都带信息量。")
                        .nuoType(NuoType.body)

                    NuoCodeBlock(
                        """
                        NuoPalette.cinnabar    // #D13415  只有 presence 与 commit
                        NuoPalette.paper       // #F9F9F8  画布
                        NuoPalette.ink         // #21201C  正文
                        """,
                        language: "swift"
                    )

                    HStack(spacing: NuoSpace.xs) {
                        NuoSourcePill(name: "NuoColor.swift", line: 96)
                        NuoSourcePill(name: "DESIGN_SPEC.md")
                    }

                    NuoFollowUps(
                        suggestions: ["给我看主界面", "侧栏怎么处理", "深色模式呢"]
                    ) { _ in }
                }
            }
        } else {
            NuoEmptyState(
                title: "在。",
                message: "问点什么，或者按住 ⌥ 直接说。",
                actionTitle: "从一份文件开始"
            ) {}
        }
    }

    private func send() {
        guard !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation(NuoCurve.snappy) {
            presence = .thinking
        }
        composerText = ""
    }

    // MARK: 演示数据

    static var demoSections: [NuoSessionSection] {
        [
            NuoSessionSection(
                title: "今天",
                items: [
                    NuoSessionItem(title: "Nuo 该怎么做 UI", timeText: "14:02", isRunning: true),
                    NuoSessionItem(title: "Osaurus 改名收尾", timeText: "11:20"),
                    NuoSessionItem(title: "M5 上的模型选型", timeText: "09:41"),
                ]
            ),
            NuoSessionSection(
                title: "昨天",
                items: [
                    NuoSessionItem(title: "插件 ABI 兼容性", timeText: "18:33"),
                    NuoSessionItem(title: "把记忆做成可审计的", timeText: "16:05"),
                    NuoSessionItem(title: "为什么编译这么慢", timeText: "10:12"),
                ]
            ),
            NuoSessionSection(
                title: "更早",
                items: [
                    NuoSessionItem(title: "本地模型的显存账本", timeText: "周一"),
                    NuoSessionItem(title: "语音打断的边界", timeText: "周一"),
                ]
            ),
        ]
    }
}
