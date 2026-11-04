//
//  NuoComposer.swift
//  NuoDesignSystem
//
//  输入 dock。
//
//  这是全应用使用频率最高的控件，也是"它是聊天工具还是智能体"的分界线。
//
//  Grok bot 的输入框只有一个动作：说。Nuo 必须有两个，因为它是能干活的：
//
//  · **对话（converse）**——回答我。快、只读、不碰你的文件。
//  · **执行（act）**——去做。会调用工具、改文件、跑命令，需要授权。
//
//  这两个模式**必须在输入框里可见**，而不是藏进某个设置项。
//  用户按下发送前的最后一秒，必须清楚地知道"它接下来会不会动我的东西"。
//  这是本设计里最重要的一条信任设计。
//
//  布局（纵向三段）：
//    附件行（有附件才出现）
//    正文输入（1 行起，最多 8 行，超出内滚）
//    操作行（左：+ @ /  中：模式段  右：模型/语音/发送）
//

import SwiftUI

// MARK: - 模式

/// 输入模式。命名刻意用动词而不是"chat"/"agent"这种行业黑话。
public enum NuoComposerMode: String, CaseIterable, Hashable, Sendable {
    /// 回答我。默认。只读工具，不写盘。
    case converse
    /// 去做。可写文件、跑命令，每次越权都要授权。
    case act

    public var label: String {
        switch self {
        case .converse: return "对话"
        case .act: return "执行"
        }
    }

    public var icon: String {
        switch self {
        case .converse: return "bubble.left"
        case .act: return "bolt.horizontal"
        }
    }

    /// 悬停提示。必须说清代价。
    public var help: String {
        switch self {
        case .converse: return "只回答问题，不动你的文件"
        case .act: return "可以调用工具、改文件、跑命令（会逐次授权）"
        }
    }
}

// MARK: - 输入 dock

public struct NuoComposer: View {
    @Binding private var text: String
    @Binding private var mode: NuoComposerMode

    private let attachments: [NuoAttachment]
    private let modelName: String
    private let presence: NuoPresenceState
    private let isStreaming: Bool
    private let placeholder: String
    private let onSend: () -> Void
    private let onStop: () -> Void
    private let onAttach: () -> Void
    private let onMention: () -> Void
    private let onVoice: () -> Void
    private let onRemoveAttachment: (NuoAttachment) -> Void

    @FocusState private var focused: Bool
    @State private var isComposing = false

    public init(
        text: Binding<String>,
        mode: Binding<NuoComposerMode>,
        attachments: [NuoAttachment] = [],
        modelName: String = "本机 · Raptor",
        presence: NuoPresenceState = .idle,
        isStreaming: Bool = false,
        placeholder: String = "说点什么，或者按住 ⌥ 直接说。",
        onSend: @escaping () -> Void,
        onStop: @escaping () -> Void = {},
        onAttach: @escaping () -> Void = {},
        onMention: @escaping () -> Void = {},
        onVoice: @escaping () -> Void = {},
        onRemoveAttachment: @escaping (NuoAttachment) -> Void = { _ in }
    ) {
        self._text = text
        self._mode = mode
        self.attachments = attachments
        self.modelName = modelName
        self.presence = presence
        self.isStreaming = isStreaming
        self.placeholder = placeholder
        self.onSend = onSend
        self.onStop = onStop
        self.onAttach = onAttach
        self.onMention = onMention
        self.onVoice = onVoice
        self.onRemoveAttachment = onRemoveAttachment
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !attachments.isEmpty {
                attachmentRow
            }

            editor

            NuoHairline()
                .padding(.horizontal, NuoSpace.md)

            controlRow
        }
        .background(
            RoundedRectangle(cornerRadius: NuoRadius.dock, style: .continuous)
                .fill(NuoColor.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NuoRadius.dock, style: .continuous)
                .strokeBorder(
                    focused ? NuoColor.accent.opacity(0.38) : NuoColor.separator,
                    lineWidth: NuoStroke.hairline
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: NuoRadius.dock, style: .continuous))
        .nuoElevation(focused ? .mid : .low)
        .animation(NuoCurve.quick, value: focused)
        // 焦点环交给系统去画会更准（它知道键盘导航的时机），
        // 这里的边框只是"正在输入"的氛围提示。
        .onTapGesture { focused = true }
    }

    // MARK: 附件

    private var attachmentRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NuoSpace.xs) {
                ForEach(attachments) { attachment in
                    HStack(spacing: NuoSpace.xs) {
                        Image(systemName: attachment.icon)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(NuoColor.textTertiary)
                        Text(attachment.name)
                            .nuoType(NuoType.caption)
                            .foregroundStyle(NuoColor.textSecondary)
                            .lineLimit(1)
                        Button {
                            onRemoveAttachment(attachment)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(NuoColor.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .help("移除")
                    }
                    .padding(.horizontal, NuoSpace.xs)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: NuoRadius.chip, style: .continuous)
                            .fill(NuoColor.surfaceSunken)
                    )
                }
            }
            .padding(.horizontal, NuoSpace.md)
        }
        .padding(.top, NuoSpace.sm)
    }

    // MARK: 正文

    private var editor: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .nuoType(NuoType.body)
            .foregroundStyle(NuoColor.textPrimary)
            .lineLimit(1 ... 8)
            .focused($focused)
            .padding(.horizontal, NuoSpace.md)
            .padding(.top, NuoSpace.sm + 1)
            .padding(.bottom, NuoSpace.sm)
            .frame(minHeight: NuoMetrics.composerMinHeight - 26, alignment: .topLeading)
            .onSubmit {
                if !canSend { return }
                onSend()
            }
    }

    // MARK: 操作行

    private var controlRow: some View {
        HStack(spacing: NuoSpace.xs) {
            NuoIconButton(systemName: "plus", help: "附件（⇧⌘A）", size: 24, action: onAttach)
            NuoIconButton(systemName: "at", help: "提及文件或记忆（@）", size: 24, action: onMention)

            Spacer(minLength: NuoSpace.sm)

            // 模式段：发送前最后一秒的"它会不会动我的东西"。
            NuoSegmented(
                options: NuoComposerMode.allCases.map { (value: $0, label: $0.label, icon: Optional($0.icon)) },
                selection: mode
            ) { newMode in
                mode = newMode
            }
            .help(mode.help)

            Spacer(minLength: NuoSpace.sm)

            NuoChip(modelName, icon: "cpu", tint: NuoColor.textTertiary)

            NuoIconButton(
                systemName: presence == .listening ? "waveform" : "mic",
                help: "语音（按住 ⌥ 说话）",
                size: 24,
                tint: presence == .listening ? NuoColor.accent : nil,
                action: onVoice
            )

            NuoSendButton(isEnabled: canSend || isStreaming, isStreaming: isStreaming) {
                if isStreaming { onStop() } else { onSend() }
            }
        }
        .padding(.horizontal, NuoSpace.sm)
        .padding(.vertical, NuoSpace.xs)
    }
}

// MARK: - 附件模型

public struct NuoAttachment: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    /// SF Symbol 名。
    public let icon: String

    public init(id: UUID = UUID(), name: String, icon: String = "doc") {
        self.id = id
        self.name = name
        self.icon = icon
    }

    /// 按扩展名猜一个图标。纯 UI 便利，不做类型判断。
    public init(name: String) {
        let ext = (name as NSString).pathExtension.lowercased()
        let icon: String
        switch ext {
        case "png", "jpg", "jpeg", "heic", "gif", "webp": icon = "photo"
        case "md", "txt", "rtf": icon = "text.alignleft"
        case "swift", "py", "js", "ts", "rs", "go", "c", "cpp": icon = "chevron.left.forwardslash.chevron.right"
        case "pdf": icon = "doc.richtext"
        case "csv", "xlsx", "numbers": icon = "tablecells"
        case "mp3", "wav", "m4a": icon = "waveform"
        default: icon = "doc"
        }
        self.init(name: name, icon: icon)
    }
}
