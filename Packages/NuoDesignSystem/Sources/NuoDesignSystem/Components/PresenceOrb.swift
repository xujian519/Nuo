//
//  PresenceOrb.swift
//  NuoDesignSystem
//
//  存在光球。
//
//  这是整套界面里唯一会**持续运动**的东西。它的职责不是装饰，而是回答
//  用户心里那个问题："它现在是死的还是活的？在听我说话吗？在替我想事吗？"
//
//  四个状态必须在**不看文字**的情况下就能分辨（这是本组件唯一的验收标准）：
//
//  · idle（待机）   —— 暗、慢呼吸（6s）、无环。像炭火快熄了。
//  · listening（在听）—— 亮、向外张、单环随音量起伏。像耳朵凑过来。
//  · thinking（在想）—— 双环反向旋转、呼吸最快（2.6s）、中心偏暗。
//                        像思路在内部打转，还没成形。
//  · speaking（在说） —— 朱转琥珀、三层声波从中心向外扩散。
//
//  性能：全部是 Core Animation 层面的 opacity / scale / rotation，
//  TimelineView 以 30fps 驱动，不做布局。不要给它加 blur 动画。
//

import SwiftUI

// MARK: - 状态

public enum NuoPresenceState: String, CaseIterable, Sendable {
    case idle
    case listening
    case thinking
    case speaking

    /// 状态的短标签。出现在身份徽标与无障碍描述里。
    public var label: String {
        switch self {
        case .idle: return "待机"
        case .listening: return "在听"
        case .thinking: return "在想"
        case .speaking: return "在说"
        }
    }

    /// 无障碍朗读。VoiceOver 需要一句完整的、带主语的话。
    public var accessibilityDescription: String {
        switch self {
        case .idle: return "智能体待机中"
        case .listening: return "智能体正在听"
        case .thinking: return "智能体正在思考"
        case .speaking: return "智能体正在说话"
        }
    }

    var breath: NuoBreath {
        switch self {
        case .idle: return .idle
        case .listening: return .listening
        case .thinking: return .thinking
        case .speaking: return .speaking
        }
    }

    /// 主色的色相偏移：只有 speaking 会转向琥珀。
    /// 单一的色相变化比四个颜色更克制，也更容易被记住。
    var tint: Color {
        switch self {
        case .speaking: return NuoPalette.amber
        default: return NuoPalette.cinnabar
        }
    }

    /// 核心亮度（0–1）。
    var coreIntensity: Double {
        switch self {
        case .idle: return 0.55
        case .listening: return 0.95
        case .thinking: return 0.72
        case .speaking: return 1.0
        }
    }
}

// MARK: - 光球

public struct PresenceOrb: View {
    private let state: NuoPresenceState
    private let diameter: CGFloat
    /// 外部音频包络（0–1）。listening / speaking 时可以接真实麦克风或 TTS 电平。
    private let level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        state: NuoPresenceState = .idle,
        diameter: CGFloat = NuoMetrics.orbCompact,
        level: Double = 0
    ) {
        self.state = state
        self.diameter = diameter
        self.level = min(max(level, 0), 1)
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            orb(at: t)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement()
        .accessibilityLabel(Text(state.accessibilityDescription))
        // 状态变化要主动通知 VoiceOver，否则盲人用户永远不知道它开始说话了。
        .accessibilityValue(Text(state.label))
    }

    // MARK: 绘制

    private func orb(at t: Double) -> some View {
        let breath = state.breath
        let extra = reduceMotion ? 0 : amplitude(at: t, breath: breath)
        let base = 1 + extra

        return ZStack {
            // ── 1. 外晕 ──────────────────────────────────────
            // 大范围的低透明度径向渐变。它让光球"照亮"周围，
            // 这是"存在感"的来源，比球体本身更重要。
            RadialGradient(
                colors: [
                    state.tint.opacity(0.22 * state.coreIntensity + extra * 1.2),
                    state.tint.opacity(0.07),
                    .clear,
                ],
                center: .center,
                startRadius: diameter * 0.10,
                endRadius: diameter * 0.72
            )
            .frame(width: diameter * 1.5, height: diameter * 1.5)
            .blur(radius: diameter * 0.10)

            // ── 2. 声波 / 外环 ───────────────────────────────
            if state == .speaking || state == .listening {
                soundRings(at: t)
            }

            // ── 3. 思考环 ────────────────────────────────────
            if state == .thinking {
                thinkingRings(at: t)
            }

            // ── 4. 球体 ──────────────────────────────────────
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.92 * state.coreIntensity),
                            state.tint.opacity(0.95),
                            NuoPalette.emberCore.opacity(0.95),
                        ],
                        center: UnitPoint(x: 0.34, y: 0.30),
                        startRadius: 0,
                        endRadius: diameter * 0.62
                    )
                )
                .frame(width: diameter * 0.78, height: diameter * 0.78)
                .scaleEffect(base)
                // 内阴影：让球有体积。用 overlay 而不是 shadow，避免污染布局。
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: max(0.5, diameter * 0.012))
                        .frame(width: diameter * 0.78, height: diameter * 0.78)
                        .scaleEffect(base)
                }
                .shadow(color: state.tint.opacity(0.45), radius: diameter * 0.12)

            // ── 5. 高光 ──────────────────────────────────────
            // 固定偏移的小白点。少了它，球会显得是"贴纸"而不是"发光体"。
            Circle()
                .fill(Color.white.opacity(0.55 * state.coreIntensity))
                .frame(width: diameter * 0.10, height: diameter * 0.10)
                .offset(x: -diameter * 0.16, y: -diameter * 0.20)
                .blur(radius: diameter * 0.02)
                .scaleEffect(base)
        }
        .frame(width: diameter, height: diameter)
        // 状态切换用弹簧，但只在颜色上——尺寸变化会打断呼吸。
        .animation(NuoCurve.fade, value: state)
    }

    // MARK: 波形

    /// 单一正弦幅度。level 只做轻微调制，避免外部数据抖动直接传导到视觉。
    private func amplitude(at t: Double, breath: NuoBreath) -> Double {
        let phase = sin(t * 2 * .pi / breath.period)
        let composite =
            breath.isComposite
            ? sin(t * 2 * .pi / (breath.period * 1.618) + 1.1) * 0.35
            : 0
        return breath.amplitude * (phase * 0.7 + composite + level * 0.25)
    }

    /// 声波：三层同心圆，相位错开 1/3 周期，向外扩散并淡出。
    private func soundRings(at t: Double) -> some View {
        ZStack {
            ForEach(0 ..< 3, id: \.self) { index in
                let offset = Double(index) / 3.0
                let progress = (t / 2.2 + offset).truncatingRemainder(dividingBy: 1.0)
                Circle()
                    .strokeBorder(
                        state.tint.opacity((1 - progress) * 0.42),
                        lineWidth: max(0.6, diameter * 0.014)
                    )
                    .frame(
                        width: diameter * (0.82 + progress * 0.72),
                        height: diameter * (0.82 + progress * 0.72)
                    )
            }
        }
        .allowsHitTesting(false)
    }

    /// 思考环：两个虚线圆反向旋转。
    ///
    /// 为什么是虚线：实线旋转看起来像"加载中"（系统控件），
    /// 虚线旋转更像"云纹在转"，更像活物。
    private func thinkingRings(at t: Double) -> some View {
        let rotation = reduceMotion ? 0 : t * 24
        return ZStack {
            Circle()
                .strokeBorder(
                    state.tint.opacity(0.38),
                    style: StrokeStyle(
                        lineWidth: max(0.7, diameter * 0.018),
                        dash: [diameter * 0.10, diameter * 0.06]
                    )
                )
                .frame(width: diameter * 1.16, height: diameter * 1.16)
                .rotationEffect(.degrees(rotation))

            Circle()
                .strokeBorder(
                    state.tint.opacity(0.20),
                    style: StrokeStyle(
                        lineWidth: max(0.6, diameter * 0.012),
                        dash: [diameter * 0.05, diameter * 0.10]
                    )
                )
                .frame(width: diameter * 1.36, height: diameter * 1.36)
                .rotationEffect(.degrees(-rotation * 0.7))
        }
        .allowsHitTesting(false)
        .opacity(0.9)
    }
}

// MARK: - 带文字的完整存在态

/// 全屏陪伴态 / 语音页的中央元素：光球 + 一句话 + 提示。
///
/// 一句话的原则是**短、用第二人称、不安慰**。
/// 不要写"我在听，请慢慢说哦～"这种语气，它会让 30 岁的用户起鸡皮疙瘩。
public struct PresenceStage: View {
    private let state: NuoPresenceState
    private let headline: String
    private let hint: String?
    private let diameter: CGFloat

    public init(
        state: NuoPresenceState = .idle,
        headline: String? = nil,
        hint: String? = nil,
        diameter: CGFloat = NuoMetrics.orbStage
    ) {
        self.state = state
        self.headline = headline ?? Self.defaultHeadline(for: state)
        self.hint = hint
        self.diameter = diameter
    }

    public static func defaultHeadline(for state: NuoPresenceState) -> String {
        switch state {
        case .idle: return "在。"
        case .listening: return "说。"
        case .thinking: return "想一下。"
        case .speaking: return ""
        }
    }

    public var body: some View {
        VStack(spacing: NuoSpace.xxl) {
            PresenceOrb(state: state, diameter: diameter)
                .padding(.vertical, NuoSpace.section)

            VStack(spacing: NuoSpace.sm) {
                if !headline.isEmpty {
                    Text(headline)
                        .nuoType(NuoType.taglineSerif)
                        .foregroundStyle(NuoColor.textPrimary)
                }
                if let hint, !hint.isEmpty {
                    Text(hint)
                        .nuoType(NuoType.callout)
                        .foregroundStyle(NuoColor.textTertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .animation(NuoCurve.fade, value: headline)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}
