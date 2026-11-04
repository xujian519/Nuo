//
//  NuoMotion.swift
//  NuoDesignSystem
//
//  动效系统。
//
//  这套界面的动效只有三种角色：
//
//  1. **应答（Answer）**——你操作了，界面回答。短、快、有弹性。100–200ms。
//  2. **过渡（Transition）**——你在两个空间之间移动（打开检查器、切页）。240–320ms。
//  3. **呼吸（Presence）**——智能体活着。永不停止，但幅度极小，不看它就不该注意到它。
//
//  最容易失败的地方是第 3 类：把它做成"发光脉冲"会立刻显得廉价。
//  呼吸必须是**形状的细微变化 + 透明度 ±8%**，周期 3.6–6 秒，且不用弹簧，
//  用正弦——弹簧有"到达感"，呼吸不能有到达感。
//

import SwiftUI

// MARK: - 时长

public enum NuoDuration {
    /// 90ms —— 按下反馈。再慢就觉得卡。
    public static let instant: Double = 0.09
    /// 140ms —— hover、颜色变化。
    public static let fast: Double = 0.14
    /// 200ms —— 标准应答。
    public static let base: Double = 0.20
    /// 320ms —— 面板进出、页面切换。
    public static let slow: Double = 0.32
    /// 480ms —— 大块内容出现（空状态、引导页）。
    public static let slower: Double = 0.48
}

// MARK: - 曲线

public enum NuoCurve {
    /// 标准应答。弹簧而不是 easeOut，因为它有"手感"。
    public static let snappy = Animation.spring(response: 0.26, dampingFraction: 0.86)
    /// 强调应答（发送键、盖章）。
    public static let press = Animation.spring(response: 0.20, dampingFraction: 0.72)
    /// 面板/空间过渡。
    public static let panel = Animation.spring(response: 0.34, dampingFraction: 0.90)
    /// 大块内容淡入。不用弹簧，避免大面积位移。
    public static let fade = Animation.easeOut(duration: NuoDuration.slow)
    /// 线性（进度条、旋转环）。
    public static let linear = Animation.linear(duration: NuoDuration.base)
    /// 快速颜色/透明度变化。hover、淡出。
    public static let quick = Animation.easeOut(duration: NuoDuration.fast)
}

// MARK: - 呼吸周期

/// 光球的呼吸参数。按状态区分，这是"读得懂的活着"。
public enum NuoBreath {
    /// 待机：慢、浅。
    case idle
    /// 在听：稍快，且有内向收敛感（等待被填满）。
    case listening
    /// 在想：最快，但不规则——用两次不同周期的正弦叠加。
    case thinking
    /// 在说：跟随音频包络，这里只给一个基准。
    case speaking

    /// 一个完整呼吸的秒数。
    public var period: Double {
        switch self {
        case .idle: return 6.0
        case .listening: return 4.2
        case .thinking: return 2.6
        case .speaking: return 1.6
        }
    }

    /// 幅度（0–1）。只允许在 0.02–0.09 之间，超过就是闪烁。
    public var amplitude: Double {
        switch self {
        case .idle: return 0.025
        case .listening: return 0.045
        case .thinking: return 0.075
        case .speaking: return 0.090
        }
    }

    /// 是否叠加第二个不同周期的波（让节奏"乱"一点点，才像有机体）。
    public var isComposite: Bool {
        switch self {
        case .idle: return false
        case .listening: return false
        case .thinking: return true
        case .speaking: return true
        }
    }
}

// MARK: - 可访问性

/// 降低动效时的替代策略。
///
/// 规范（必须遵守）：系统开启"减弱动态效果"时，
/// · 弹簧 → 交叉淡入（0.2s）
/// · 呼吸 → 静态，仅保留一个 12% 的透明度差
/// · 任何超过 24pt 的位移 → 取消
public enum NuoMotionPolicy {
    public static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeInOut(duration: NuoDuration.fast) : animation
    }

    public static func resolvedDuration(_ duration: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? min(duration, NuoDuration.fast) : duration
    }
}

// MARK: - 过渡

extension AnyTransition {
    /// 面板从右侧推入（检查器）。
    public static var nuoTrailingPanel: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .opacity
        )
    }

    /// Sheet 从下方生长。
    public static var nuoSheet: AnyTransition {
        .asymmetric(
            insertion: .offset(y: 12).combined(with: .opacity),
            removal: .opacity
        )
    }

    /// 一条消息出现：不要从下往上滑（像聊天软件），
    /// 而是轻微缩放 + 淡入，像"浮现"。
    public static var nuoMessage: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.985, anchor: .topLeading).combined(with: .opacity),
            removal: .opacity
        )
    }

    /// 盖章：从 1.18 倍收缩到 1，带轻微过冲。
    public static var nuoStamp: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.86, anchor: .center).combined(with: .opacity),
            removal: .scale(scale: 0.96).combined(with: .opacity)
        )
    }
}

// MARK: - 呼吸视图

/// 给任意视图套一层呼吸。
///
/// 实现上不用 `withAnimation(.repeatForever)` 改 scale（那会触发每帧布局），
/// 而是用 `TimelineView` 驱动一个只改 `opacity` / `scaleEffect` 的微弱变化——
/// 这两者都在 Core Animation 层，不引起 SwiftUI 重排。
public struct NuoBreathing<Content: View>: View {
    private let breath: NuoBreath
    private let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ breath: NuoBreath = .idle, @ViewBuilder content: () -> Content) {
        self.breath = breath
        self.content = content()
    }

    public var body: some View {
        if reduceMotion {
            content.opacity(0.88)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = sin(t * 2 * .pi / breath.period)
                let secondary =
                    breath.isComposite
                    ? sin(t * 2 * .pi / (breath.period * 1.618) + 1.1)
                    : 0
                let combined = (phase + secondary * 0.5) / 1.5
                content
                    .scaleEffect(1 + combined * breath.amplitude)
                    .opacity(1 - breath.amplitude * 0.55 + combined * breath.amplitude * 0.55)
            }
        }
    }
}
