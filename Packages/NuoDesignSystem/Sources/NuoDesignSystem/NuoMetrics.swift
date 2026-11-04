//
//  NuoMetrics.swift
//  NuoDesignSystem
//
//  尺寸、间距、圆角、海拔。
//
//  间距只用 4 的倍数（外加 2 和 6 两个半档）。
//  不允许出现 5、7、9、13、15、18 这类"手感值"——它们会让整个界面的
//  垂直节奏在长列表里累积成肉眼可见的错位。
//

import SwiftUI

// MARK: - 间距

/// 垂直节奏的原子单位。命名按"用途"而不是数字，方便审查一致性。
public enum NuoSpace {
    /// 2 —— 图标与它的文字之间。
    public static let hair: CGFloat = 2
    /// 4 —— 紧凑元素内部。
    public static let xxs: CGFloat = 4
    /// 6 —— 标签与徽标。
    public static let xs: CGFloat = 6
    /// 8 —— 同一信息组内的行间距。
    public static let sm: CGFloat = 8
    /// 12 —— 组与组之间（最常用）。
    public static let md: CGFloat = 12
    /// 16 —— 卡片内边距。
    public static let lg: CGFloat = 16
    /// 20 —— 区块内边距。
    public static let xl: CGFloat = 20
    /// 24 —— 区块之间。
    public static let xxl: CGFloat = 24
    /// 32 —— 页面级分区。
    public static let section: CGFloat = 32
    /// 48 —— 大留白。
    public static let gutter: CGFloat = 48
    /// 64 —— 空状态上方留白。
    public static let breathing: CGFloat = 64
    /// 96 —— 启动页留白。
    public static let expanse: CGFloat = 96
}

// MARK: - 圆角

/// 圆角分四档，且与"这一层离用户多近"相关：
/// 越贴近操作（按钮、输入）越小越锐，越像容器（卡片、浮层）越大越柔。
public enum NuoRadius {
    /// 3 —— 印章、徽标、头像方块。刻意接近直角，才有"盖上去"的硬度。
    public static let seal: CGFloat = 3
    /// 6 —— Chip、标签、行内代码。
    public static let chip: CGFloat = 6
    /// 8 —— 按钮、输入框、分段控件。与既有 `inputCornerRadius = 8` 一致。
    public static let control: CGFloat = 8
    /// 12 —— 卡片、消息块容器。
    public static let card: CGFloat = 12
    /// 20 —— 输入 dock、浮层。与既有 `FloatingInputCard` 的 20 一致，避免无谓返工。
    public static let dock: CGFloat = 20
    /// 20 —— Sheet 顶部。
    public static let sheet: CGFloat = 20
    /// 999 —— 胶囊。
    public static let capsule: CGFloat = 999
}

// MARK: - 线宽

public enum NuoStroke {
    /// 发丝线。所有分隔线、卡片描边。**不要因为屏幕是 Retina 就加倍**——
    /// SwiftUI 会自己按 scale 渲染，写 1 就是 1pt。
    public static let hairline: CGFloat = 1
    /// 强调描边（选中态、拖拽目标）。
    public static let emphasis: CGFloat = 1.5
    /// 焦点环。
    public static let focus: CGFloat = 2
}

// MARK: - 布局常量

/// 这些数字是整套界的骨架，改动它们等于改版。
public enum NuoMetrics {

    // ── 窗口 ────────────────────────────────────────────────
    /// 主窗口默认尺寸。1060 是"260 侧栏 + 800 对话"的最小舒适值。
    public static let chatWindowSize = CGSize(width: 1060, height: 700)
    /// 主窗口最小尺寸。低于它侧栏必须自动折叠。
    public static let chatWindowMin = CGSize(width: 800, height: 620)
    /// 管理窗口（设置 / 洞察 / 模型）。
    public static let managementWindowSize = CGSize(width: 940, height: 640)

    // ── 侧栏 ────────────────────────────────────────────────
    /// 侧栏默认宽度。
    public static let sidebarWidth: CGFloat = 260
    /// 侧栏最小 / 最大。
    public static let sidebarMin: CGFloat = 260
    public static let sidebarMax: CGFloat = 380
    /// 侧栏可折叠的阈值：窗口窄于这个值就自动收起。
    public static let sidebarAutoCollapseBelow: CGFloat = 880
    /// 会话行高。
    public static let sessionRowHeight: CGFloat = 30
    /// 会话行左右内缩。
    public static let sessionRowInset: CGFloat = 10

    // ── 对话 ────────────────────────────────────────────────
    /// 【关键】正文栏宽上限。超过它，眼睛回扫会累。
    public static let readingColumn: CGFloat = 720
    /// 对话区左右最小内边距。
    public static let threadPadding: CGFloat = 24
    /// 两条消息之间的间距（同一个人连续发言要更小，见 MessageRow.roleSpacing）。
    public static let messageSpacing: CGFloat = 24
    /// 同一发送者连续消息的间距。
    public static let messageSpacingTight: CGFloat = 10
    /// 头像尺寸（圆形）。
    public static let avatar: CGFloat = 26
    /// 「存在点」尺寸——消息头像旁表示智能体状态的小圆点。
    public static let presenceDot: CGFloat = 7

    // ── 输入 dock ───────────────────────────────────────────
    /// dock 宽度上限（和正文栏宽对齐，视觉上"接着说话"）。
    public static let composerWidth: CGFloat = 720
    /// dock 距窗口底部的距离。
    public static let composerBottomInset: CGFloat = 20
    /// dock 单行高度。
    public static let composerMinHeight: CGFloat = 52
    /// dock 最大高度（超过后内部滚动）。
    public static let composerMaxHeight: CGFloat = 208
    /// dock 内边距。
    public static let composerPadding: CGFloat = 12
    /// 发送键直径。
    public static let sendButton: CGFloat = 30

    // ── 检查器 ──────────────────────────────────────────────
    /// 右侧检查器宽度。只在需要时出现（文件改动、记忆来源、工具详情）。
    public static let inspectorWidth: CGFloat = 380
    /// 检查器出现的窗口宽度阈值。
    public static let inspectorAppearAbove: CGFloat = 1180
    /// 检查器可拖范围。真实实现里与「对话列保底 440」联动。
    public static let inspectorMin: CGFloat = 300
    public static let inspectorMax: CGFloat = 520

    // ── 头部 ────────────────────────────────────────────────
    /// 自绘标题栏高度（系统 titlebar 已隐藏）。
    public static let titlebarHeight: CGFloat = 38
    /// 红绿灯按钮直径。
    public static let trafficLight: CGFloat = 12
    /// 红绿灯间距。
    public static let trafficLightGap: CGFloat = 8
    /// 自绘标题栏左侧留白（给红绿灯）。
    public static let trafficLightInset: CGFloat = 18

    // ── 触达区域 ────────────────────────────────────────────
    /// 最小可点击边长。低于 28 的小图标必须靠这个扩热区。
    public static let hitTarget: CGFloat = 28
    /// 触达区域外扩（用于 .contentShape 与 padding）。
    public static let hitExpansion: CGFloat = 6

    // ── 印章 ────────────────────────────────────────────────
    /// 侧栏顶部印章尺寸。
    public static let sealSmall: CGFloat = 22
    /// 常规印章。
    public static let seal: CGFloat = 40
    /// 启动页大印。
    public static let sealLarge: CGFloat = 96

    // ── 光球 ────────────────────────────────────────────────
    /// 输入 dock 里的微型存在点。
    public static let orbInline: CGFloat = 18
    /// 侧栏/标题栏的常态光球。
    public static let orbCompact: CGFloat = 28
    /// 存在态主视图。
    public static let orbStage: CGFloat = 220
    /// 全屏陪伴态的最大直径。
    public static let orbFullscreen: CGFloat = 340
}

// MARK: - 海拔

/// 阴影只有三档，且**越靠内容区越淡**。
///
/// 一个容易犯的错：给每张卡片都加阴影。这里的规矩是——
/// 只有"离开画布浮起来"的元素（dock、Popover、Sheet）才有阴影，
/// 平铺在画布上的卡片只用发丝线，不用阴影。
public enum NuoElevation {
    /// 贴地。列表行 hover。
    case none
    /// 轻浮。输入 dock、分段控件。
    case low
    /// 中浮。Popover、下拉菜单。
    case mid
    /// 高浮。Sheet、对话框、拖拽中的卡片。
    case high

    public var shadowRadius: CGFloat {
        switch self {
        case .none: return 0
        case .low: return 10
        case .mid: return 18
        case .high: return 32
        }
    }

    public var shadowY: CGFloat {
        switch self {
        case .none: return 0
        case .low: return 2
        case .mid: return 6
        case .high: return 14
        }
    }

    public var shadowOpacity: Double {
        switch self {
        case .none: return 0
        case .low: return 0.07
        case .mid: return 0.10
        case .high: return 0.16
        }
    }
}

extension View {
    /// 应用一档海拔。阴影颜色永远用墨色的极小透明度，
    /// 不要用纯黑——纯黑阴影像脏污，尤其在暖底上。
    public func nuoElevation(_ level: NuoElevation) -> some View {
        self.shadow(
            color: NuoPalette.ink.opacity(level.shadowOpacity),
            radius: level.shadowRadius,
            x: 0,
            y: level.shadowY
        )
    }
}
