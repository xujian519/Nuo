# Nuo UI 设计规范

> 版本 1.0 · 2026-11-04
> 对象仓库：`/Users/xujian/projects/Nuo`（Osaurus fork，纯 SwiftUI + AppKit 消息层）
> 事实基础：`research/ui-inventory.md`（对真实代码的只读考古，含行号）
> 可执行产物：`NuoDesignSystem/`（SwiftUI 包，已 `swift build` 通过）、`prototype/`（可点原型）

---

## 0. 一页读

**Nuo 现在不缺功能，缺三样东西：**

| 缺什么 | 证据（真实计数） | 本规范怎么补 |
|---|---|---|
| 统一令牌层 | 字面字号 4,893 处 / 走主题的字号仅 206 处（4%）；字面 `padding()` 3,344 处 | 第 3 节 + `NuoDesignSystem` |
| 「在场」的视觉主体 | 聊天头是 52pt 的 `Color.clear`；`OrbShader.metal` 全仓 0 引用、未进 target | 第 5.2 节 + `PresenceOrb` |
| 从引导到主界面的连续叙事 | 引导用独立调色板（`#0091ff`、40pt、16 圆角），主界面 `#0a84ff`、26pt、10 圆角 | 第 5.11 节 |

**一句话方向：纸与印。** 暖灰宣纸做底，唯一的彩色是印泥朱红，且只出现在两个时刻——**它活着**，和**你按下发送**。

**为什么不是第二个 Grok。** Grok 的黑底发光是"未来感"，代价是长盯屏累，且几乎全行业在抄。纸的暖灰 8 小时更耐看，也让"本地、私人、可归档"在直觉上成立——这正是 Nuo 的立身之本。

---

## 1. 目标与非目标

### 1.1 目标

1. 建立一套**可编译、可复用**的令牌层（颜色 / 字阶 / 间距 / 圆角 / 线宽 / 海拔 / 动效），并把它接进现有 `CustomTheme` 体系，而不是另起一套平行主题。
2. 给出**十二屏**的完整规范：布局、组件、状态、动效、键盘、空/错/载。
3. 让「它是什么状态」在任何一屏都不需要读文字就能判断——靠光球的节奏，不靠状态图标。
4. 让「它会不会动我的东西」在按下发送前的一秒内清楚可见（输入 dock 的「对话 / 执行」模式）。
5. 每一处改动都能落到具体文件，且标注了返工量与风险。

### 1.2 非目标（本轮明确不做）

- **不重构消息渲染层。** 消息流是 `NSTableView` + `NativeMessageCellView`（3,907 行），不是 SwiftUI。本轮只做**视觉与令牌**，不动数据源与 cell 复用。
- **不重命名任何内部标识**（`OsaurusCore`、`osaurus_*`、`ai.osaurus.*`）——沿用 `docs/brand/INTERNAL-IDENTIFIERS.md` 的冻结契约。
- **不做移动端 / iPad 版适配。**
- **不做主题市场 / 用户自定义配色**。本轮把主题收敛为「纸 / 夜纸 / 跟随系统」三选一；`CustomTheme` 的可定制能力保留但默认不暴露入口。
- **不引入第三方 UI 依赖**（无 SPM 组件库、无 WebView 渲染）。

---

## 2. 品牌层

### 2.1 名字与印

「诺」＝答应下来的事。产品第一性：**承诺要被兑现，且留在本机。**

印章（`NuoSealMark`）是这个承诺的物证——盖下去就不再改。它在界面里只允许出现在三处：

1. **身份位**：侧栏顶部 / 标题栏左侧，代表"这是谁在跟你说话"（22pt，白文）。
2. **品牌位**：引导页、关于面板（96pt，朱文带四角回纹）。
3. **仪式位**：完成、落定、归档时的一次盖章（`NuoStampEffect`，一次 340ms）。

> 禁止：把印章放进普通按钮、标签、空状态插画、加载动画。印章一旦变成装饰，它的重量就没了。

小尺寸规则（物理极限，不是妥协）：**< 40pt 不画回纹与内边框**，只留印边 + 单字；否则 22pt 里四个回纹会糊成一团墨点。

### 2.2 两条颜色纪律

**纪律一：朱红只对应一个正在发生的事件。**
界面上任何一个红色像素，都必须能回答"现在正在发生什么"。检查方法：给界面截图转灰度，如果某个红色区域在灰度图上找不到对应的内容变化，它就是装饰 → 删掉。

**纪律二：红 = 重要，所以错误必须冗余编码。**
危险色与朱红同族（`#8E2F22` / `#F0715C`），这是刻意的：用户只需要学会"红 = 得看一眼"。代价是**错误状态绝不允许只靠颜色**——必须同时有图标（`exclamationmark` 等）与文字。这条在 §8.1 有强制检查项。

### 2.3 版式性格

- 中文用 PingFang SC，西文 SF Pro，**同一行由系统混排**，不手动配基线。
- 衬线（New York / Songti）**只用于品牌时刻**：印章旁的题字、启动页标语、空状态那"一句话"。正文、按钮、标签一律无衬线。
- 数字一律等宽（`.monospacedDigit()` 或 SF Mono）——token 计数、延迟、金额这类会跳变的数值，宽度抖动比数值本身更刺眼。

---

## 3. 令牌

> 实现：`NuoDesignSystem/Sources/NuoDesignSystem/{NuoColor,NuoType,NuoMetrics,NuoMotion,NuoSurface}.swift`
> 原型：`prototype/style.css`（CSS 变量与 Swift 常量逐字对应，两边不同步 = bug）

### 3.1 颜色

所有色值成对定义（light/dark），通过 `NSColor(name:dynamicProvider:)` 在运行时解析。**组件里不写 `if colorScheme == .dark`**——SwiftUI 的 `@Environment(\.colorScheme)` 在 Sheet/Popover/独立 NSWindow 里可能落后一帧，会出现顶栏与内容错色的闪动。

| 令牌 | light | dark | 用途 | 对比度（light / dark） |
|---|---|---|---|---|
| `paperSunken` | `#EFEAE0` | `#100F0C` | 窗底、侧栏 | — |
| `paper` | `#F7F4ED` | `#161512` | 画布 | — |
| `paperRaised` | `#FCFAF6` | `#1E1C18` | 卡片、dock | — |
| `paperFloat` | `#FFFFFF` | `#26231E` | 菜单、Popover | — |
| `ink` | `#1C1A17` | `#F2EEE4` | 一级文字 | **15.8:1 / 15.8:1** |
| `inkSecondary` | `#565149` | `#ADA69A` | 二级文字 | 7.2:1 / 7.6:1 |
| `inkTertiary` | `#6F6959` | `#8C8679` | 时间戳、占位符 | **4.98:1 / 5.04:1** |
| `inkGhost` | `#98907F` | `#5F5A53` | **仅装饰**，不承载文字 | 2.88:1 / 2.67:1 |
| `hairline` | `#E2DCD0` | `#2C2925` | 所有 1px 线 | — |
| `hairlineStrong` | `#CFC7B8` | `#3A362F` | 浮层边界 | — |
| `cinnabar` | `#C93A2B` | `#EB5B45` | 存在 + 承诺 | **4.64:1 / 5.32:1** |
| `cinnabarDeep` | `#A32C20` | `#C9472F` | 按下态 | 6.5:1 / 3.9:1（非文字） |
| `cinnabarWash` | `#F3E2DE` | `#3A211C` | 10% 底、选中 | — |
| `amber` | `#C97B24` | `#F0A94A` | 说话态光球 | 3.01:1 / 9.1:1（**仅图形**） |
| `success` | `#3F7A42` | `#6FAE72` | 成 | 4.69 / 6.93 |
| `warning` | `#9A6414` | `#D9A24B` | 警 | 4.54 / 8.02 |
| `danger` | `#8E2F22` | `#F0715C` | 危 | 7.41 / 6.28 |

**灰阶只有一套。** 现有仓库里 `LightTheme/DarkTheme`（暖黑暖白）与 `CustomTheme.lightDefault/darkDefault`（macOS 冷灰蓝）两套调色板并存，是本轮第一个要收敛的对象——见 §9.1。

### 3.2 字阶

向真实默认值对齐（`CustomTheme.darkDefault`：title 26 / heading 18 / body 15 / caption 12 / code 13）。**刻意不改既有字号**——`theme.font` 只覆盖 4%，逐级换字号等于动 4,893 处，收益远小于风险。

| 角色 | 字号 / 字重 / 字距 / 行距 | 说明 |
|---|---|---|
| `display` | 40 / 600 / -0.8 / +2 | 只在引导页与"关于" |
| `title1` | 26 / 600 / -0.4 / +2 | 页面主标题 |
| `title2` | 18 / 600 / -0.2 / +1 | Sheet、分组 |
| `headline` | 15 / 600 / -0.1 / +1 | 卡片标题、发送者 |
| `body` | 15 / 400 / 0 / **+5** | 对话正文。行高 24 = 1.6 倍，中文长文下限 |
| `callout` | 13 / 400 / 0 / +3 | 列表副标题、说明 |
| `caption` | 12 / 400 / +0.1 / +2 | 时间戳、字数、模型名 |
| `captionStrong` | 12 / 600 / +0.4 / +2 | 分组头（小字号需要正字距才立得住） |
| `mono` | 13 / 400 / monospaced | 数值、标识符 |
| `code` | 13 / 400 / monospaced / +4 | 代码块 |
| `sealSerif` | 17 / serif / +1.6 | 印章旁题字 |

### 3.3 间距 · 圆角 · 线宽

- **间距**只用 4 的倍数（外加 2 / 6 两个半档）：`2 · 4 · 6 · 8 · 12 · 16 · 20 · 24 · 32 · 48 · 64 · 96`。禁止 5 / 7 / 9 / 13 这类手感值——它们在长列表里会累积成肉眼可见的错位。
- **圆角**五档：`3 印 · 6 chip · 8 控件 · 12 卡片 · 20 dock/浮层`。其中 **8 与 20 取自现有代码**（`inputCornerRadius = 8`、`FloatingInputCard` 圆角 20），刻意不改，避免无谓返工。
- **线宽**永远 1px。`FloatingInputCard` 现有的 `0.75 / 1.5 / 0.5` 三种边框按状态切换是历史遗留，本轮统一为 1（聚焦用颜色与阴影区分，不用加粗）。

### 3.4 海拔

| 档 | radius / y / opacity | 用途 |
|---|---|---|
| `none` | 0 | 平铺卡片 |
| `low` | 10 / 2 / 0.07 | 输入 dock、分段控件 |
| `mid` | 18 / 6 / 0.10 | Popover、下拉 |
| `high` | 32 / 14 / 0.16 | Sheet、授权卡 |

阴影颜色用**墨色的极低透明度**，不用纯黑——纯黑阴影在暖底上像脏污。判据：**它会跟着滚动一起移动吗？** 会 → 面（无阴影，只有发丝线）；不会 → 浮层（有阴影）。

### 3.5 动效

| 角色 | 时长 | 曲线 | 用在哪 |
|---|---|---|---|
| 应答 | 90ms | spring(.20, .72) | 按下 scale 0.97 |
| 悬停 | 140ms | easeOut | 颜色、背景 |
| 标准 | 200ms | spring(.26, .86) | 展开/收起、分段切换 |
| 过渡 | 320ms | spring(.34, .90) | 面板进出、页面切换 |
| 大块淡入 | 480ms | easeOut | 空状态、引导 |

**呼吸**（唯一持续动画）：周期 6.0 / 4.2 / 2.6 / 1.6s，幅度 2.5% / 4.5% / 7.5% / 9%。用正弦，**不用弹簧**——弹簧有"到达感"，呼吸不能有到达感。

现有 `animationDurationQuick/Medium/Slow = 0.15 / 0.25 / 0.35` 与 `spring 0.35 @ 0.82` 已接近本规范，**不动**；只新增"呼吸"这一类。

---

## 4. 外壳与几何

### 4.1 真实几何（现状，需尊重）

| 面 | 真实值 | 出处 |
|---|---|---|
| 聊天窗默认尺寸 | 目标屏 `visibleFrame`（整块可用区） | `ChatWindowManager.swift:1128` |
| 聊天窗最小尺寸 | **800 × 620** | `ChatWindowState.swift:399` |
| 侧栏宽 | 可拖 **260…460**，持久化默认 240（被夹到 260） | `ChatView.swift:10077`、`:9256` |
| 消息容器 | `min(chatWidth, 1100)` | `ChatView.swift:10274` |
| 输入卡 | 宽同容器（1100），左右缩进 20，圆角 20 | `FloatingInputCard.swift:4963` |
| 检查器 | 可拖 **300…520**，设计开合宽 **380** | `ChatView.swift:10104` |
| 聊天列保底 | 440 | `ChatView.swift:10108` |
| 侧栏顶部留白 | 40（给红绿灯） | `ChatSessionSidebar.swift:135` |
| 管理窗 | 940 × 640 | `WindowManager.swift:57` |
| 引导窗 | 1000 × 640，**深色专用** | `OnboardingDesign.swift:14` |

### 4.2 本规范的建议值（与现状的差量最小化）

| 项 | 现状 | 建议 | 理由 |
|---|---|---|---|
| 侧栏宽 | 260（默认值 bug 见 §9.4） | **260 默认 / 上限 380** | 380 足够放"智能体 + 记忆数"，420+ 只会稀释正文 |
| 消息容器 | 1100 | **1100 不动，内部文字块锁 720** | 卡片/表格可以铺满 1100，一段话不能。这是本轮**最重要的一个几何决定** |
| 输入卡 | 1100 宽 | **720 宽** | 与正文块同宽，"接着说话"的错觉；缩进仍是 20→居中 |
| 检查器 | 380 | **380 不动** | 已合理 |
| 圆角 | 输入 20 / 控件 8 / 卡 12 | 不动 | 只在设置区把 10 统一到 12 |
| 窗口红绿灯 | 系统标准 | **不动** | 见 §4.4 |

### 4.3 三栏与让位

```
┌────────── 1060（默认）──────────────────────────────┐
│ 侧栏 260 │  对话列（≤1100，文字锁 720）  │ 检查器 380 │
└──────────┴─────────────────────────────┴───────────┘
```

- 检查器打开需 `窗口宽 ≥ 侧栏 + 440 + 300`，否则侧栏**临时退场**（现有 `sidebarStepsAside` 逻辑保留）。
- 本轮唯一改动：检查器出现阈值从"窗口宽 ≥ 1180"改为**与现有让位公式保持一致**（现在是两组数各算各的，会出现"检查器出现但侧栏不退场，聊天列被压到 380"的死角）。

### 4.4 侧栏的透镜：三个，不是一个（含一个 IA 决策）

**现状**：左栏已不是「会话侧栏」，而是 `Agents | Projects` 双透镜（`ChatSessionSidebar.swift:129-132`），历史会话被搬到右侧 inspector 的 `history` 面板（`ChatWindowState.swift:132-137`）。

**决策**：改为**三透镜 `会话 | 智能体 | 项目`，默认落在「会话」**。

理由：个人智能体的日常动作是"接着上次说"，不是"浏览我有几个 agent"。把最近会话放进右侧 380pt 宽、需要先开检查器才能看到的面板里，等于把最高频的入口藏在第二层。Grok / Claude / ChatGPT 全部是会话优先，这不是巧合。

**代价与规避**：
- 现有 `history` 面板**不删**，降级为「当前 agent 的完整历史 + 搜索」（会话透镜只显示最近 8 条/组，深挖仍走面板）。这样两条路径各有分工，而不是二选一。
- 复用现有 `SidebarLensBar` 组件（`:236-245`），只多一个 lens case，**不需要新写切换器**。
- 会话行沿用 `AgentSidebarRow` 的度量（行高 30–34、头像 26、分组头 12 semibold + tracking 0.4），只把头像换成 presence 光球、行尾换成时间/运行态。
- 现有「没有折叠能力，只有整体隐藏或拖宽」的限制保留——但**折叠按钮（⌘B）必须在侧栏顶部可见**，否则窄窗口下用户找不到它（现在藏在 NSToolbar 里，窗口全屏时还要经过 `ChatFullScreenHeaderView` 复刻一套）。

**不改的**：`Agents | Projects` 两透镜的内容与分组结构（workspace sections / shared / discovered）全部保留，只把入口从"默认"降为"第二个透镜"。

### 4.5 标题栏：不要跟 AppKit 打架

现状是**真实的 `NSToolbar`**（`.unified`，三件套：侧栏按钮 / tab strip / File Changes+History+Pin 合成项）。原型里那套"静止为墨点的自绘红绿灯"在 CSS 里很好看，但在 AppKit 里要 hack `standardWindowButton`，**升级 macOS 就会碎**。

**决定：保留系统红绿灯与 NSToolbar，只做三件事：**
1. `titlebarSeparatorStyle = .none`（已有）。
2. 中段 `ChatTabStripView` 换 Nuo 令牌（track 28 / 圆角 6 / 选中 = 抬升面 + 发丝线）。
3. 不在标题栏放任何彩色——标题栏的职责是"可拖动"，不是"展示品牌"。

> 原型里的墨点红绿灯仅作视觉探索，**不进入实施清单**。

---

## 5. 十二屏

每屏格式：**目的 → 布局 → 关键决定 → 状态 → 与现状的差量**。

### 5.1 对话（旗舰屏）

**目的**：让"继续上次"零摩擦，让"它做了什么"可审计，让"它是文档"而不是"聊天"。

**布局（纵向）**

```
38pt  NSToolbar（保留）
────  52pt 透明头（现状）→ 改为 0：头部不用占位，直接交给 tab strip
      消息流（NSTableView，容器 1100）
        · 你的话：抬升卡 + 左侧 2pt 朱红细线
        · 过程脊：折叠行「做了 4 件事 · 8.4s」
        · 它的回答：**无容器**，直接长在画布上，文字宽 720
      底部：输入 dock（720 宽，浮在内容上）+ 下方 96pt 渐隐
```

**三个关键决定**

1. **不做聊天气泡。** 气泡是即时通讯语法，会暗示"来回发消息"。智能体的回答是文档：能长、有代码、有表格、能被引用。**你的话被收进卡片（因为说完了），它的话全部展开（因为它是内容）。**
2. **过程脊默认折叠，但折叠时仍显示步数与耗时。** 用户不关心细节，但需要"我没偷偷做事"的最小证据。展开 = "我在审计你"。这与现有 `NativeActivityGroupView`（"Worked for 12s · 6 steps"）语义一致，只换视觉。
3. **输入 dock 的模式段**（对话 / 执行）必须常驻可见。这是本设计最重要的一条**信任设计**：按下发送前的最后一秒，用户必须知道"它接下来会不会动我的文件"。

**状态**

| 态 | 表现 |
|---|---|
| 空 | 印章水印（16%）+ 衬线「在。」+ 一行提示 + 一个动作 |
| 流式 | 正文尾部 2pt 朱红光标（呼吸 0.55s），不用"▍"字符（会占字宽导致跳行） |
| 过程进行 | 脊头显示当前步文案 + 光球 `thinking`（14pt），不用转圈 |
| 等待授权 | 授权卡从底部升起（见 §6.2），脊头变琥珀点 |
| 错误 | 脊头红点 + 展开后该步带 `exclamationmark` + 错误文案（**三重编码**，见 §2.2） |

**与现状的差量**：不改消息层数据结构；改 `NativeMessageCellView` 的排版常量（容器 1100 → 内部 720）、去掉助手侧的卡片背景、`FloatingInputCard` 宽度 1100→720 并加模式段。

---

### 5.2 存在态 / 语音

**目的**：回答"它现在是死的还是活的"。这是全 App 唯一允许"几乎什么都不放"的屏。

**布局**：无侧栏、无标题栏、无 tab。中央光球 220pt，下方一句衬线（「在。」/「说。」/「想一下。」），再下方一行 12pt 提示，底部 21 根 2.5px 音量柱 + 三个快捷指令。

**四个状态必须不看文字就能分辨**（这是本组件唯一的验收标准）：

| 态 | 节奏 | 环结构 | 语义 |
|---|---|---|---|
| `idle` | 6.0s 慢呼吸 | 无环 | 像炭火快熄了 |
| `listening` | 4.2s | 单环随包络外张 | 耳朵凑过来 |
| `thinking` | 2.6s | 双**虚线**环反向旋转 | 思路在内部打转（实线会像系统加载控件） |
| `speaking` | 1.6s | 朱→琥珀 + 三层声波外扩 | 唯一改变色相的状态 |

**为什么只有一个色相变化**：颜色是最贵的信号。用掉三个色相表示状态，就没有色相留给"这件事需要注意"。节奏能表达的信息量远大于色相。

**文案纪律**：短、第二人称、不安慰。允许「在。」「说。」「想一下。」；禁止「我在听，请慢慢说哦～」（30 岁用户会起鸡皮疙瘩）。

**与现状的差量**：`Views/` 下**不存在** presence 类视图，所有语音 UI 都是事务型浮层（按住才出现）。这是唯一**全新工作量**的屏。`OrbShader.metal` 是可用起点但未进 target——**建议先用纯 SwiftUI 实现**（`PresenceOrb` 已可运行，无 Metal 依赖），Metal 版作为后续性能优化，别让一个 shader 挡住整个屏。

---

### 5.3 智能体

**目的**：让 agent 有"性格"，而不是一台设备的配置页。

**布局**：两列卡片（`flexible(min 300)`，保留现有网格）+ 下方一张「当前智能体配置」卡。

- **头像用印章字，不用吉祥物。** 现有关联的六色小恐龙 `AgentMascot` 是上一代品牌资产；印章字（诺/探/匠/记）在同一尺寸下更安静，也能直接承载"这个 agent 是干什么的"。**迁移成本低**（`AgentAvatarView` 单点替换），但**品牌收益最大**。
- 卡片只显示三件事：角色一句话、模型 chip、记忆条数。其余进详情。
- 详情用**一张卡 + 六行**（人格 / 声音 / 主题 / 能力 / 记忆范围 / 写入权限），而不是现有 12 个 DetailTab。12 个 tab 是工程结构，不是用户的心智结构。

**与现状的差量**：`AgentsView.swift` 9,538 行里 90% 是能力开关。**本轮不动能力配置页**，只重排列表 + 详情首屏。

---

### 5.4 记忆

**目的**：把"数据库视图"变成"关系视图"——每条记忆都能点回原话。

**布局**：左列条目（标题 + 类型 tag + 来源 pill + 置信条），右栏「为什么记这条」（原话摘录 + 作用范围 + 最近使用）。

**关键决定**：**没有来源的记忆不写。** 这是可审计性的最低标准，也是本地智能体相对云产品的信任差异点。现有 5 个 tab 里的 `diagnostics` 与 `settings` 占据 2/5 导航位，把产品价值埋在工程面板后面——建议把 diagnostics 降级为页脚链接。

**与现状的差量**：`MemoryView.swift` 1,335 行 + 3 个组件文件。本轮只做 `memories` 这一 tab 的重排，其余保留。

---

### 5.5 工具与插件

**目的**：让"我能做什么"以第一人称表达，并让授权边界一眼可见。

**布局**：左列工具行（名称 + 权限 tag：只读/写入/网络 + 开关），右栏「授权」示例卡 + 插件列表。

**关键决定**：**工具默认全关。** 你开一个，才存在一个。现有列表以"包 / 版本 / 来源"为主键，读起来像 npm 界面；改成按**风险**分组（只读 / 写入 / 网络），开关放行尾。

**授权卡是全 App 最重的组件**（见 §6.2）。

---

### 5.6 知识

**目的**：让知识库**可读**（现状全页是"注册文件夹 → 建索引 → 开关授权"，用户看不到里面有什么）。

**布局**：搜索 + 类型标签过滤（概念/规则/案例/法条）+ 两列卡片。

**关键决定**：**草稿与事实不能混。** 未确认的卡片有明显标记，且不进检索——这条在视觉上必须成立，否则用户会引用一张自己还没确认的卡片。

---

### 5.7 工作区

**目的**：把"这次会话动过什么"变成可回滚的账本。

**布局**：文件树 260 + 主区「本次会话动过的文件」（每条 +/− 与一句话说明）+ 底部"它还想改 2 个文件"的提示卡。

**关键决定**：把待授权的事**显式摆出来**，而不是等它弹窗。用户可以在看到全貌后再决定，而不是在被突袭时决定。

---

### 5.8 洞察

**目的**：从"账本"变成"叙事"——这个月花了多少、省了多少、发生了什么异常。

**布局**：三张数字卡（对话轮次 / 本机占比 / 省下的云费用）+ 迷你折线 + 模型使用条形 + 运行状况行。

**关键决定**：**只算数，不上报。** 这句话要写在页头，而不是藏在隐私政策里。

---

### 5.9 日程

**目的**：让"未来两周会发生什么"可见（现状是任务记录列表，看不见时间）。

**布局**：时间轴式列表（每行：任务 + rrule 人话 + 下次运行 + 上次结果 + 开关）。

**关键决定**：**无人值守的边界写在页面上**——定时任务只允许读取与生成草稿，任何写入要等你回来确认。"它可以在你睡觉时整理，但不能替你签字。"

---

### 5.10 设置

**目的**：从"引擎舱清单"（30 个 tab：Runtimes / Providers / Sandbox / Server / Watchers）变成"我想改什么"。

**布局**：左导航 220 + 右内容（分组卡片 + 行），搜索框常驻顶部。

**关键决定**：

1. **统一头部语法。** 现状 `ManagerHeader*`（22pt 标题）与 `SettingsSection`（分组卡）两套并存，是设置区最大的视觉不一致来源。**保留 `SettingsSection`，淘汰 `ManagerHeader*`**（30 个页面里绝大多数用的是后者，需要一个过渡期，但必须一次定方向）。
2. 每一项都必须在 `SettingsSearchIndex`（229 条）里有一行，且 `title` 与该控件屏幕上的字面完全一致——否则搜索找不到，等于没做。
3. 新增一页「当前配置摘要」：一眼看懂"我这套 Nuo 是怎么配的"（模型 / 记忆范围 / 已授权工具 / 数据目录）。

---

### 5.11 引导

**目的**：交代"东西在你机器里"，而不是介绍功能。

**布局**：1000×640 窗口，大印 96 + 衬线「一 诺」+ 三行说明 + 三个模型选项 + 一个主按钮。

**关键决定**：**把引导的独立调色板并入令牌层。** 现状 `OnboardingPalette`（`#0091ff`、40pt、16 圆角）与主界面（`#0a84ff`、26pt、10 圆角）没有共享任何一层，导致"引导结束视觉陡降"。这是 909 行令牌的去向问题，也是本规范里**性价比最高的合并**。

注意：现有引导窗是**深色专用**（`window.appearance = .darkAqua` + 硬注入 `DarkTheme()`）。改为跟随主题时，务必保留 `DarkTheme()` 注入点或一起迁移——`AppDelegate.swift:2612` 硬引用，删早了引导窗会挂（见 §9.4 第 4 条）。

---

### 5.12 模型

**目的**：回答"该用哪个"，而不是"仓库里有什么"。

**布局**：本机模型列表（显示**内存占用条**而不是参数量）+ 云端 provider 行 + 内存策略卡。

**关键决定**：**本机优先，云端需手动选。** 现有列表以体积/量化为技术主键；改成以"用途 + 机器能不能扛"为主键。4B 模型在 16GB 机器上一次只能跑一个——这件事要在界面上说出来，而不是等 OOM。

---

## 6. 跨屏组件

### 6.1 命令面板（⌘K）

跳到会话 / 智能体 / 工具 / 记忆 / 设置项。没有它，对话超过 200 条后侧栏就是考古现场。尺寸 520 宽，最大高 320 + 头 44。

### 6.2 授权卡（最重的组件）

**三个决定：**

1. **不用系统 Alert。** 系统 Alert 会被习惯性连点掉，而这里需要被读。
2. 把"将发生什么"写成**一句人话**（"它会把 NuoColor.swift 里的 4 个色值改成新令牌"），不写代码路径。
3. **「允许一次」是主按钮，「总是允许」是次按钮。** 默认值必须是最小授权。破坏性操作**永远不做实心红**——实心红会让误触的代价变大。

现有 `ToolPermissionPromptService` 已有独立 panel，本轮只换内容与按钮权重。

### 6.3 空状态

只有一句话（≤14 字）+ 一行 12pt 说明 + 最多一个按钮。印章水印降到 16%——它是纸上的旧印，不是新盖的。

### 6.4 Toast

位置在 **dock 上方 12pt**，不是窗口底部——它属于输入区的语境。现状是独立 panel（`ToastContainerView`），若保留 panel 则需要按 dock 位置重算锚点。

### 6.5 追问建议

现有 `FollowUpSuggestionsBar` 是"插在助手消息下的一行"，**不是浮在输入区上** —— 这个选择是对的，保留；只换视觉（胶囊 → 无底发丝线）。

---

## 7. 动效规范（汇总）

| 场景 | 参数 | 禁止 |
|---|---|---|
| 按钮按下 | scale 0.97 / 90ms / spring(.20,.72) | 用颜色变深表达按下（太慢，手感会断） |
| 悬停 | 背景/颜色 / 140ms easeOut | 位移 |
| 过程脊展开 | 320ms spring(.34,.90) | 高度动画（NSTableView 里会抖） |
| 消息出现 | scale 0.985 + 淡入 / 320ms | 从下方滑入（那是聊天软件语法） |
| 面板推入 | move(edge:.trailing) + 淡入 | 缩放 |
| 盖章 | scale 1.55→1 + 旋转 -6°→0 / 340ms spring(.34,.58) | 用在高频操作上 |
| 呼吸 | 正弦 / 1.6–6s / 幅度 2.5–9% | 弹簧、blur 动画 |

**减弱动态效果**（`accessibilityReduceMotion`）时必须降级：弹簧 → 交叉淡入 0.2s；呼吸 → 静态，仅保留 12% 透明度差；>24pt 的位移 → 取消。**这一点现有代码完全没有覆盖**，属于新增要求。

---

## 8. 无障碍

### 8.1 强制项

1. **对比度**：正文 ≥4.5:1（已核，见 §3.1 表）；UI 组件边界 ≥3:1；**`inkGhost` 不得承载任何文字**（2.88:1）。
2. **错误三重编码**：颜色 + 图标 + 文字，缺一不可（因朱红与危险色同族，见 §2.2）。
3. **光球**：`accessibilityLabel` 播报完整句子（"智能体正在思考"），`accessibilityValue` 播报状态词；状态变化要主动通知 VoiceOver（`AccessibilityNotification.Announcement`），否则盲人用户永远不知道它开始说话了。
4. **触达区**：任何可点元素 ≥28×28pt（小图标靠 `contentShape` 扩热区）。现有侧栏行尾的 24×24 按钮不达标。
5. **减弱动效**：见 §7。
6. **焦点环**：键盘导航可见焦点（`NuoColor.focusRing`，2pt，外扩 2）。

### 8.2 键盘

| 键 | 行为 |
|---|---|
| ⌘N / ⌘T | 新对话（当前窗口新 tab） |
| ⌘B | 显隐侧栏 |
| ⌥⌘I | 显隐检查器 |
| ⌘K | 命令面板 |
| ⌘F | 会话内查找（现有 `ChatFindBar`） |
| ⌥（按住） | 语音输入 |
| ⌘↩ | 发送（可与 ↩ 并存，↩ 保持现状） |
| esc | 关浮层 / 退出语音 |

---

## 9. 实施计划

### 9.1 阶段一：令牌层（1–2 天，风险低，杠杆最高）

> **状态：已落地（未提交）。** 实现在 `Packages/NuoDesignSystem` + `Models/Theme/NuoThemeSkin.swift`，
> 细节与回滚方式见 `docs/NUO_UI_PHASE1.md`（本包内副本：`PHASE1_LANDED.md`）。
> 玻璃已全部关闭（见 `PHASE1_LANDED.md` §5）。
> 与原计划的两处偏差：① 没有新增「纸/夜纸」预设，而是直接把它们做成了 `Dark`/`Light` 这两个默认皮肤
> （避免主题列表里出现两套等价项）；② 额外关闭了 `followsSystemAccent`——开着它会让系统强调色
> 静默覆盖朱红。

1. 把 `NuoDesignSystem` 作为本地 SPM 包接入 `Packages/`（不发布，直接 path 依赖）。
2. **桥接**：`CustomTheme.colors` 的 28 个 hex 映射到 `NuoPalette`；新增「纸 / 夜纸」两个内建预设（`CustomTheme.allBuiltInPresets` 已有 `paper`，可作为起点改造）。
3. 递增 `ThemeConfigurationStore.currentBuiltInThemeSchema`（6 → 7），否则老用户拿不到新默认皮肤（注释里已写明这条纪律）。
4. 决定 `LightTheme/DarkTheme` 的去向：**只保留给引导窗**，其余全部走 `CustomTheme`。这一步不做，两套调色板会一直互相打补丁。

**DoD**：全 App 换肤到纸/夜纸；`theme.*Color` 的 5,770 处引用**零修改**（因为是换主题数据，不是改调用点）。

### 9.2 阶段二：字号与间距令牌化（工作量最大，3–5 天）

按热区排序（`.system(size:)` 最多的文件）逐个文件替换为 `NuoType.*`：

`Agent/AgentsView.swift` 246 → `Settings/ProvidersView.swift` 134 → `Schedule/SchedulesView.swift` 127 → `Settings/ServerView.swift` 115 → `Settings/RemoteProviderEditSheet.swift` 108 → `Settings/SearchView.swift` 98 → `Plugin/PluginsView.swift` 94

**不要**一次性 sed 4,893 处——按文件改、每改一个跑 `make ci-test`，并用截图对比。

**DoD**：上述 7 个文件字号 100% 走令牌；`theme.font` 覆盖率从 4% 提升到 ≥25%。

### 9.3 阶段三：存在态（全新工作量，2–3 天）

1. `PresenceOrb`（SwiftUI 版，已在 `NuoDesignSystem` 里可运行）。
2. 接入点：侧栏身份位（22pt）、消息头像（16pt）、输入 dock 语音键、独立语音页（220pt）。
3. 状态来源：现有 `SessionActivityMonitor`（已有实时步骤文案）→ 映射到 `idle/listening/thinking/speaking`，**不新建状态机**。
4. Metal 版延后：需要先往 `project.pbxproj` 加编译源，再把 `orbEffect` 挂进 `.colorEffect`——**否则会静默返回原色**（`OrbShader.metal` 目前全仓 0 引用）。

**DoD**：四个状态在 4 个尺寸（16/22/28/220）下都能分辨；`accessibilityReduceMotion` 开启后不崩不闪。

### 9.4 阶段四：逐页重排（可并行，每屏 0.5–1 天）

优先级：对话 → 空态 → 智能体列表 → 设置头部统一 → 记忆/工具/知识 → 其余。

**已知的坑（考古报告原样摘录，必须提前安排）：**

1. `chatSidebarWidth` 默认 240 被 `clampSidebarWidth` 夹到 260 → **默认值永远取不到**，任何"恢复默认宽度"都会落在 260。修：默认值直接写 260。
2. `WindowConfiguration.chat` 是半死配置：`usePanel / titlebarAppearsTransparent / hideStandardButtons / autosaveKey` 对聊天窗**全部不生效**（聊天窗由 `ChatWindowManager` 自建）。改它会"看起来改了但没改"。
3. 字号有三套来源：主题 `fontScale`（等比）、字面 `.system(size:)`、AppKit `NSFont.systemFont`。**消息层完全不读主题字号**，只读颜色。
4. `AppDelegate.swift:2612` 硬注入 `DarkTheme()` 给引导窗（有意为之）。删 `DarkTheme` 前先改这里，否则引导窗会挂。
5. `OrbShader.metal` 未进 target（见 §9.3）。

---

## 10. 不做清单（No-Gos）

- ❌ 黑底发光 / 霓虹渐变 / 玻璃拟态堆叠（与"纸"冲突）
- ❌ 第二个强调色（蓝、紫、青一律不进主界面；代码块里的 `codeString` 绿是唯一例外）
- ❌ 聊天气泡（见 §5.1）
- ❌ 自绘红绿灯（见 §4.4）
- ❌ 卡片套卡片（一屏最多一层"面"）
- ❌ 超过三个的追问建议
- ❌ 用颜色单独表达错误
- ❌ 用系统 Alert 承载授权
- ❌ 在标题栏放品牌色

---

## 11. 验收清单

### 视觉纪律

- [ ] 截图转灰度：所有红色区域都能对应到一个内容变化
- [ ] 全 App 只有一套灰阶（`LightTheme` 与 `CustomTheme` 的冷灰蓝已收敛）
- [ ] 没有任何 1.5px / 2px 装饰线（焦点环除外）
- [ ] 每一屏只有一个 15pt 以上的标题

### 无障碍

- [ ] 正文对比度 ≥4.5:1（脚本扫描 16 个色对）
- [ ] 所有错误态同时有图标 + 文字
- [ ] 光球四态都有 VoiceOver 播报
- [ ] 开启"减弱动态效果"后无崩溃、无闪烁、无 >24pt 位移
- [ ] 全键盘可完成：新对话 → 输入 → 发送 → 读回复 → 展开过程脊

### 工程

- [ ] `theme.*Color` 调用点零修改即换肤
- [ ] `currentBuiltInThemeSchema` 已递增
- [ ] 消息容器 1100 / 文字块 720 的边界在两个缩放档（默认、放大字号）下都成立
- [ ] 输入 dock 宽度 720 时，长文本不出现横向抖动

---

## 附录 A · 令牌 ↔ 现有字段映射

| 现有 | 位置 | 新令牌 |
|---|---|---|
| `ThemeProtocol.primaryBackground` | `Theme.swift:43-140` | `NuoColor.canvas` |
| `secondaryBackground / tertiaryBackground` | 同上 | `surface / surfaceSunken` |
| `primaryText / secondaryText / tertiaryText` | 同上 | `textPrimary / textSecondary / textTertiary` |
| `accentColor / accentColorLight` | 同上 | `accent / accentPressed` |
| `primaryBorder / secondaryBorder / focusBorder` | 同上 | `separator / border / focusRing` |
| `successColor / warningColor / errorColor` | 同上 | `success / warning / danger` |
| `cardCornerRadius = 12` | `Theme.swift:146-228` | `NuoRadius.card` |
| `inputCornerRadius = 8` | 同上 | `NuoRadius.control` |
| `bubbleCornerRadius = 20` | 同上 | 废弃（不做气泡） |
| `bodySize 15 / captionSize 12 / codeSize 13 / titleSize 26 / headingSize 18` | 同上 | `NuoType` 同名 |
| `animationDurationQuick/Medium/Slow` | 同上 | `NuoDuration.fast/base/slow` |
| `animationSpring(response:damping:)` | 同上 | `NuoCurve.panel` |
| `cardShadowRadius/Y` | 同上 | `NuoElevation.low/mid` |
| `SidebarStyle.width = 240` | `SharedSidebarComponents.swift:15` | `NuoMetrics.sidebarWidth (260)` |
| `sidebarWidthRange 260…460` | `ChatView.swift:10077` | `sidebarMin 260 / sidebarMax 380` |
| `inspectorWidthRange 300…520` | `ChatView.swift:10104` | `inspectorMin/Max`，默认 380 |
| `defaultMaxContentWidth = 1100` | `MessageTableRepresentable.swift:37` | 容器保持；`readingColumn = 720` |
| `composerHorizontalInset = 20` | `ChatView.swift:11156` | `composerBottomInset`（横向改居中 720） |
| `SettingsGroupMetrics 16×12 / 圆角 10` | `SettingsKit.swift:47-51` | `NuoSpace.md/sm` + `Radius.card(12)` |
| `OnboardingPalette / Typography / Layout` | `OnboardingDesign.swift:18/66/101` | 全部映射到 `NuoPalette / NuoType / NuoSpace` |

## 附录 B · 修改点清单（按风险排序）

| 风险 | 文件 | 改什么 |
|---|---|---|
| 中 | `Models/Theme/CustomTheme.swift:847/948` | 新增纸/夜纸预设；替换 lightDefault/darkDefault |
| 中 | `Models/Theme/ThemeConfigurationStore.swift:17` | schema 6→7 |
| 中 | `Views/Onboarding/DesignSystem/OnboardingDesign.swift` | 令牌接入（保留 1000×640） |
| 中 | `Views/Management/ManagerHeader.swift` | 淘汰，向 `SettingsSection` 收敛 |
| 低 | `Views/Chat/FloatingInputCard.swift` | 宽度 1100→720、加模式段、圆角保持 20 |
| 低 | `Views/Chat/NativeMessageCellView.swift` | 容器内文字块限 720、去助手侧卡片 |
| 低 | `Views/Chat/ChatSessionSidebar.swift` | 默认宽 260、行高 30、选中竖线 |
| 低 | `Views/Agent/AgentAvatarView.swift` | 吉祥物 → 印章字 |
| 高（新） | `Views/Presence/` | 新建存在态屏 + `PresenceOrb` 接入 |
| 高 | `App/osaurus.xcodeproj/project.pbxproj` | 若做 Metal 光球，需加编译源 |

---

*规范结束。所有数字可复算：对比度由 WCAG 2.1 相对亮度公式计算，代码计数来自 `research/ui-inventory.md` 的实测脚本输出。*
