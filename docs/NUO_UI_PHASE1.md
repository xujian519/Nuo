# Nuo UI · 阶段一：令牌层与主题桥接

> 状态：**已落地（已提交）**
> 日期：2026-11-04
> 设计文档：`docs/nuo-ui/DESIGN_SPEC.md` §9.1 + `docs/nuo-ui/DECISIONS.md`（逐字快照，
> 源交付包仍在 `~/Pictures/Nuo-UI/`；快照说明见 `docs/nuo-ui/README.md`）
> 目标：只改主题数据层，不动 5,770 处 `theme.*Color` 调用点，让整个 App 一次性换到「纸与印」。

---

## 1. 改了什么

| 文件 | 类型 | 内容 |
|---|---|---|
| `Packages/NuoDesignSystem/` | 新增 | 设计令牌包（色彩 / 字阶 / 间距 / 圆角 / 动效 / 材质 + 组件）。本地 SPM 包，不发布 |
| `Packages/OsaurusCore/Package.swift` | 改 | 加 `.package(path: "../NuoDesignSystem")` 与 target 依赖 |
| `Packages/OsaurusCore/Models/Theme/NuoThemeSkin.swift` | 新增 | 「纸 / 夜纸」两套 `ThemeColors` 的**唯一真源**，全部取自 `NuoHex` |
| `Packages/OsaurusCore/Models/Theme/CustomTheme.swift` | 改 | `darkDefault` / `lightDefault` 的 31 行色值块各替换成一行 `NuoThemeSkin.*`；两个预设的 `followsSystemAccent` 改为 `false` |
| `Packages/OsaurusCore/Models/Theme/ThemeConfigurationStore.swift` | 改 | `currentBuiltInThemeSchema` 6 → **7**（关键：不递增，老用户拿不到新皮肤） |
| `Tests/Theme/ThemeAppearanceModeTests.swift` | 改 | 默认皮肤断言改为新色板；新增「所有内建主题都不跟随系统强调色」 |
| `Tests/Theme/ThemeSystemAccentTests.swift` | 改 | 跟随行为从"默认开启"改为"需要显式开启"；identity 测试改用主题自身的 accent |
| `Models/Theme/NuoThemeSkin.swift`（阶段 1.5） | 改 | 新增 `paperGlass` / `nightGlass`：玻璃全关 |
| `Views/Management/SharedSidebarComponents.swift`（阶段 1.5） | 改 | 侧栏底面 `cardBackground` → `sidebarBackground`（1 行） |

**没有动的**：`ThemeProtocol`、`LightTheme`/`DarkTheme`（仍供引导窗使用）、`CustomizableTheme`、任何视图文件、任何 `theme.*Color` 调用点。

---

## 2. 三个必须解释的决定

### 2.1 关掉 `followsSystemAccent`

`darkDefault` / `lightDefault` 原先显式 `followsSystemAccent: true`。打开时，`CustomizableTheme` 会用**系统强调色**（系统设置里的蓝/紫/粉）重新推导 `accentColor / focusBorder / cursorColor / selectionColor / sidebarSelectedBackground / infoColor`——也就是说，朱红会在主题构建那一刻被**静默替换**成系统蓝，整套「纸与印」直接塌掉，而且不会有任何报错。

所以：朱红是品牌语义（存在 / 承诺），不是可替换的装饰 → 内建主题一律不跟随。
跟随能力**保留给用户自定义主题**（`ThemeColors.applyingAccent(_:isDark:)` 与相关测试都还在）。

> 代价（诚实记录）：把系统强调色设成非默认值的用户，在这个版本里看不到自己的强调色了。若之后要做回这个偏好，正确形态是一个独立的「跟随系统强调色」开关，默认关闭，而不是把它绑死在默认预设上。

### 2.2 `buttonBackground` 必须填中性面，不能填墨色

在「纸」这个方向里，主按钮是朱红实心。很容易顺手把 `buttonBackground` 设成墨色（`#1C1A17`），因为它在某些主题里看起来就像"深色按钮"。

但仓库里 `theme.buttonBackground` 的 11 处调用（`CircularIconButton`、`SimpleComponents`、`DirectoryPickerView`、`StatusPanelView`…）全是**图标按钮的底**。填墨色会让侧栏、目录选择器、状态面板里所有次级图标按钮变成黑块。

→ 映射为 `paperRaised`（抬升面），`buttonBorder` 取 `hairlineStrong`。

### 2.3 `infoColor` 不给蓝色

这套系统只有纸与朱两个色相。`infoColor` 有 33 处调用，但都是**状态着色**（搜索无结果、provider 诊断），不承载"这是链接"的语义（链接走 `accentColor`）。

→ 映射为二级墨色 `#565149` / `#ADA69A`，靠图标而不是色相区分信息态。

---

## 3. 迁移与回滚

**迁移**：`builtInThemeSchemaVersion` 从 6 涨到 7，`installBuiltInThemesIfNeeded()` 会强制重写所有内建主题文件。持有 `activeThemeId = …0001/…0002` 的用户下次启动即为新皮肤，无需操作。

**回滚**（两条独立的路）：
1. **数据层**：把 `currentBuiltInThemeSchema` 改回 6 并重新启动 → 内建主题文件被重写回旧色板。
2. **代码层**：`git checkout -- Packages/OsaurusCore/Models/Theme/CustomTheme.swift`（`NuoThemeSkin.swift` 与设计系统包可以留着，不引用即无副作用）。

旧色板没有丢：pre-2102 的 Osaurus 配色仍作为 **Nuo Dark / Nuo Light** 两个预设可选。schema 6 引入的 macOS 原生色板被取代（可通过主题 JSON 复原）。

---

## 4. 怎么验证

```bash
# 1) 令牌包自检
swift build --package-path Packages/NuoDesignSystem

# 2) 主包编译
swift build --package-path Packages/OsaurusCore --target OsaurusCore

# 3) 主题相关测试
swift test --package-path Packages/OsaurusCore --filter Theme
```

**Live 验收**（按 AGENTS.md 的 release proof 口径）：

已留证：设置 ▸ 主题页的浅色 / 深色与实际观感，以及「主题卡按钮去红」前后对比 —
截图在交付包 `shots/20-app-settings-paper.png`、`21-app-settings-night.png`、
`23-app-themes-fixed-paper.png`；引导窗仍是旧调色板（`22-app-onboarding-legacy.png`，
阶段四才并入，见 §6）。

未做（下面第 3–5 项，阶段二开工前应先补）：
1. ~~用隔离的开发产物启动 App，确认首屏就是暖灰纸底、强调色是朱红而不是系统蓝。~~（已留证，限设置窗口）
2. ~~打开 设置 ▸ 主题，确认列表里出现的是新配色。~~（已留证；「缩略图与主界面一致」仅肉眼核对过浅色）
3. 切换 深色 / 浅色 / 跟随系统，确认没有"半新半旧"的中间态。
4. 退出重启，确认选择被持久化；再把系统强调色改成紫色，确认朱红**不**跟着变（这是 2.1 的验收点）。
5. 抽查 4 个高密度页面（对话、设置、智能体、插件）确认没有浅色文字落在浅底上——`tertiaryText` 从 2.8:1 提到了 4.98:1，理论上只会变好，但硬编码的白色前景需要肉眼过一遍。

---

## 5. 阶段 1.5：关掉玻璃（已落地）

### 5.1 为什么关

`NSVisualEffectView` 的材质会把背景色**去饱和、往中性灰拉**。暖纸底一进材质就发灰，朱红被稀释——这正是「纸」这个方向最不能接受的失真。纸的质感来自"没有中间介质"：底色就是底色。

深色同理：材质会把桌面/壁纸的颜色渗进来，一块暖黑的"纸"不该随壁纸变色。

另外，`glassEnabled` 为真时聊天背景会叠一层 `ThemedGlassSurface` + 两层渐变（`ChatView.swift:11286`），在 1060×700 的窗口里纯属浪费 GPU。

### 5.2 三个开关必须同时关

| 开关 | 消费者 | 只关 `enabled` 会怎样 |
|---|---|---|
| `enabled` | 聊天背景、PromptCard、Toast、输入卡浮层 | — |
| `sidebarEnabled` | `SharedSidebarComponents.SidebarBackground:126` | 侧栏仍是毛玻璃 |
| `inputEnabled` | `FloatingInputCard:6241` | 输入卡仍是毛玻璃 |

→ 两个预设都设置为三个全 `false`，其余参数（material / blur / opacity / tint / edgeLight / backing）**刻意保留旧值**：用户在主题编辑器里重新打开玻璃时拿到的是可用的一组值，而不是一堆 0。

### 5.3 一处视图改动：侧栏底色

`SidebarBackground` 的第 1 层此前用 `theme.cardBackground`。关掉玻璃后这一层变成不透明，于是**侧栏比画布还亮**（`#FCFAF6` vs `#F7F4ED`）——视觉上反客为主：侧栏是"被推远"的一层，卡片才该比画布亮。

改为 `theme.sidebarBackground`（`#EFEAE0`，比画布沉一档）。这是阶段一唯一的视图改动，1 行 + 3 行注释。

**影响面要讲清楚**：这个组件被聊天侧栏、检查器、设置侧栏共用，所以 **8 个内建主题 + 所有用户主题的侧栏底色都会随之改变**（从"卡片色"变成各自主题里既有的 `sidebarBackground`）。多数主题里这两者只差几个百分点且方向正确，但这是一个**跨主题**的视觉变化，如果不想牵连旧主题，可以改成"仅玻璃关闭时用 `sidebarBackground`"的条件式——我选择了统一，因为两套底色逻辑本身就是这个组件的历史债务。

### 5.4 验证与回滚

- 编译：`Build complete`（186s，包含这个被 197 个文件读取的视图）。
- 测试：`ThemeAppearanceModeTests` 7 项、`ThemeSystemAccentTests` 6 项全绿；新断言钉住"三个开关全 false"。
- 回滚：把 `NuoThemeSkin.paperGlass` / `.nightGlass` 的三个开关改回 `true` 即可；侧栏那一行单独 revert 也不影响配色。

## 6. 已知的、留给后续的

| 项 | 说明 | 建议 |
|---|---|---|
| ~~玻璃效果~~ | **已落地**（阶段 1.5）：两个默认主题的玻璃全关，侧栏底色改为 sunken | — |
| 字号 / 间距 | 未动（4,893 处字面字号 / 3,344 处字面间距） | 阶段二，按 `DESIGN_SPEC.md` §9.2 的 7 个热区文件逐个替换 |
| 引导窗 | 仍是 `DarkTheme()` 硬注入 + 独立调色板 | 阶段四并入令牌层；迁移前**不要**删 `LightTheme/DarkTheme` |
| 上游合并 | `Package.swift` 与 `CustomTheme.swift` 会有冲突 | 冲突处理：`Package.swift` 保留 `.package(path:)` 与 target 依赖两行；`CustomTheme.swift` 保留 `colors: NuoThemeSkin.*` 与 `followsSystemAccent: false` |
| 气泡字段 | `ThemeMessages` 的 11 个字段已不被新设计使用 | 保留但停止读取，不要删（用户主题 JSON 里可能有值） |
