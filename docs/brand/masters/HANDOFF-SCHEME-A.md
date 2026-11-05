# Nuo 品牌方案 A — 实现交接

状态：设计已确认（2026-11-05）  
仓库：`/Users/xujian/projects/Nuo`  
决策：印章红主标 + 深底；AppIcon 以照片压平母版描矢量；菜单栏以 AI 印芯手修后作 template。

## 0. 美术前置（实现前或并行）

| 产出 | 底稿 | 要求 |
|---|---|---|
| `nuo-seal-full.svg` (+ 1024 PNG) | `appicon-master-from-photo-1024.png` | 外框+回纹+海棠内框+印文；色 `#F8141C` / 白；边缘干净，无朱砂齿 |
| `nuo-glyph-template.svg` (+ 模板 PNG) | `glyph-ai-filled-transparent.png` | 仅印芯实心剪影；对照原印手修；18px 可辨；无边框/回纹 |
| （可选）`nuo-wordmark.svg` | 新绘 | 「Nuo」字标；outline 路径；勿改旧 osaurus wordmark 路径充数 |

未出 SVG 前可用 PNG 母版先换图验收布局，但 **发布前必须换矢量导出**。

## 1. 色板

写入 `Packages/OsaurusCore/Views/Onboarding/DesignSystem/OnboardingDesign.swift`（及全局 Accent）：

- `sealRed` = `#F8141C`
- `sealRedPressed` = `#C41018`
- `sealRedMuted` = `#F8141C` @ 22%
- `paper` = `#FAF7F2`
- 保留 `windowBackground` `#1E1E1E`、label 白阶
- 链接/选中/主强调：由 `accentBlue`/`accentCyan`/`dinoGreen`（作品牌）改为 `sealRed*`
- `dinoGreen` 仅保留为 success / 状态绿点（可改名 `successGreen`）
- `App/osaurus/Assets.xcassets/AccentColor.colorset`：写入 sealRed（sRGB）

## 2. 资源替换（禁止改 imageset 目录名）

| 目标 | 动作 |
|---|---|
| `App/osaurus/Assets.xcassets/AppIcon.appiconset/*` | 由 full-seal 导出各尺寸 |
| `App/osaurus/osaurus-app-icon.icon/` | 同步新图层/填充；去掉恐龙蓝 |
| `App/osaurus/Assets.xcassets/osaurus.imageset` | 印芯 template（白剪影）；供 `NSImage(named: "osaurus")` + `isTemplate` |
| `Packages/OsaurusCore/Resources/Assets.xcassets/osaurus-main.imageset` | 深底完整印或印+字标；替换恐龙团绘 |
| `osaurus-logo` / `osaurus-logo-wordmark`（App 与 Core 两侧若有） | 换内容为 Nuo mark/wordmark |
| `assets/dmg-bg.tiff` | 目视；含旧标则重出 |

## 3. 欢迎页文案

`OnboardingWelcomeView.swift` + `Localizable.xcstrings`（及 6 语）：

- 去掉 Dino / 恐龙比喻
- 标题草案（中）：`本地智能体，说到做到。`
- 标题草案（英）：`Local agents that keep their word.`
- 副文：本机运行、对话/文件/密钥可留本机、无需账号或云
- CTA 可维持白底 pill，或改 `sealRed` 实心白字
- 链接色改暖红/sealRed，不再用 accentBlue

## 4. 代码触点（线索）

- `AppDelegate.installStatusItem`：`NSImage(named: "osaurus")`，18×18，`isTemplate = true`
- `OnboardingWelcomeView` 右栏 `Image("osaurus-main")`
- `OnboardingDesign.swift` / `OnboardingComponents` 中 blue/green 强调
- WhatsNew / ChatModelPicker 等 `osaurus-logo` template 引用：内容换了即可

## 5. 冻结 / 不做

- 不改 imageset / 资源目录名（Swift 按名引用）
- 不改 `Brand.swift` 与 `scripts/brand` 冻结契约
- 本轮不清空全部恐龙插画集（brain/create 等可二期）
- 不擅自合并 PR；验证需重编 `Nuo.app`

## 6. 验收

1. Dock / About / Cmd-Tab：完整朱文印，无恐龙  
2. 菜单栏 18px：浅/深菜单栏均可辨印芯  
3. 欢迎三屏：无 Dino 文案与团绘；强调色朱砂  
4. `scripts/brand/verify.sh` 绿  
5. `make app`（或既有 xcodebuild）产出 `Nuo.app` 目视通过  

## 7. 建议提交信息

`brand(ui): scheme A seal mark, splash, and accent red`
