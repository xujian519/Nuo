# Nuo 品牌改造方案

> 状态（2026-11-06 核对）：已确认。Phase 0–1 已落地（Phase 1 于 2026-11-04 完成编译验收）；Phase 2 源码完成、缺实机证明；Phase 3 除 B 类外部事实外已落地；Phase 4/5 部分落地；Phase 6 受仓库外凭据阻塞。
> 仓库：`/Users/xujian/projects/Nuo`（Osaurus 的 fork）
> 基线提交：`c0da268a`
> 相关文件：`scripts/brand/`（可执行层）、`docs/brand/INTERNAL-IDENTIFIERS.md`（冻结契约）、`docs/brand/UPSTREAM-SYNC.md`（上游同步 Runbook）

---

## 1. 一句话

这个仓库要继续从上游 `osaurus-ai/osaurus` 合并更新，所以改名不能是全仓 `sed`。
方案把改名收敛成一个**可重放层**：`brand.json`（唯一真源）+ `rules/*.json`（幂等规则）+ `apply.sh`（每次 merge 后重放）+ `verify.sh`（CI 守卫）+ `baseline.json`（棘轮快照）。
估算改动面约 180 个文件，而不是深度改名会带来的约 1400 个。

---

## 2. 目标与非目标

### 目标

1. 用户能看到的一切都是 `Nuo` / `nuo`：App 名、菜单栏、关于面板、权限文案、6 语言界面文案、图标、DMG 文件名、CLI 命令、数据目录、URL scheme、Bonjour 服务名、Keychain 条目、bundle id。
2. 旧数据不丢：会话、模型、密钥、配置一次性自动迁移，且旧数据整版保留可回滚。
3. 外部契约不碎：Swift 模块名、插件 ABI、HF 模型 id、工具名、HTTP 头、环境变量等保持原样。
4. 上游可持续合并：`git merge upstream/main` 之后跑一次 `scripts/brand/apply.sh` 即可回到 Nuo 状态，冲突面集中在约 20 个文件。

### 非目标

- 不改 `LICENSE`（`Copyright (c) 2026 Osaurus, Inc.` 保留原文，等书面指示）。
- 不改 Swift 模块名 / target 名 / 目录名 / 工程文件名（`OsaurusCore`、`Packages/OsaurusCore/`、`osaurus.xcodeproj`、`osaurus.xcworkspace`）。
- 不改 1584 处文案的**实现方式**（不做集中常量重构），只改文案内容本身。
- 不改内部工程文档与证据目录（`docs/**` 除白名单外、`docs/evidence/**`、`results/**`、`reports/**`）。
- 不重建 Sparkle 发布链路（Phase 6 前用占位 feed，自动更新关闭）。

---

## 3. 已确认决策

| # | 决策 | 取值 |
|---|---|---|
| 1 | 改名深度 | 完整品牌替换（显示名 / 6 语言 / 图标 / 产物 / CLI / bundle id / 数据根 / Keychain / URL scheme / Bonjour） |
| 2 | bundle id | `com.nuo.app`（测试 target：`com.nuo.app.tests` / `com.nuo.app.uitests`）。需要自有域名后才算最终值 |
| 3 | 旧数据 | 一次性自动迁移，copy 不 move，旧数据整版保留 |
| 4 | 外部契约 | 冻结（见第 5 节），不随改名变动 |
| 5 | 上游跟进 | 继续跟随，规则化重放 + CI 守卫 |
| 6 | 版权署名 | `LICENSE` / `Credits.rtf` / `NSHumanReadableCopyright` 本轮不动 |
| 7 | 图标与 wordmark | 先上占位字标，等美术输入（outline 化矢量路径）替换 |
| 8 | Sparkle | nuo 版先关闭自动更新，feed 指向 `https://nuo.app/appcast.xml`（尚未发布） |
| 9 | 文档范围 | README + `COMMUNITY_EVALS.md` + `docs/plugins/**` + 内置 `Guide/**`；其余文档冻结 |
| 10 | Keychain ACL 被拒 | 接受系统弹窗重填；绝不静默变空（读失败要在 UI 明确提示） |

---

## 4. 命名契约

| 面 | 旧 | 新 | 备注 |
|---|---|---|---|
| 显示名 | Osaurus | **Nuo** | `CFBundleDisplayName`、菜单栏、关于面板 |
| bundle id | `com.dinoki.osaurus` | `com.nuo.app` | 驱动 TCC / UserDefaults 域 / Keychain ACL / Sparkle |
| 可执行名 | `osaurus` | `Nuo` | `PRODUCT_NAME = Nuo`，产物 `Nuo.app` |
| CLI 命令 | `osaurus` | `nuo` | 构建产物仍是 `osaurus-cli`（内部名，不改） |
| 内嵌 helper | `Contents/Helpers/osaurus` | `Contents/Helpers/nuo` | 旧名保留为相对软链一个版本 |
| URL scheme | `osaurus://` | `nuo://` | 一个版本内双注册 + 双解析；新链接一律生成 `nuo://` |
| Bonjour | `_osaurus._tcp` / `_osaurus-mobile._tcp` | `_nuo._tcp` / `_nuo-mobile._tcp` | 一个版本内双注册 + 双浏览 |
| 数据根 | `~/.osaurus` | `~/.nuo` | 迁移期读旧写新 |
| App Support | `~/Library/Application Support/com.dinoki.osaurus` | `~/Library/Application Support/com.nuo.app` | 旧路径继续参与迁移链 |
| Keychain | `com.osaurus.*` / `ai.osaurus.*` / `com.dinoki.osaurus.*` | `com.nuo.*` / `ai.nuo.*` | 14 个 service 改名 + 懒迁移；`ai.osaurus.id` 冻结不动（令牌归上游 `*.osaurus.ai` 身份服务） |
| UserDefaults 键 | `ai.osaurus.*` | 不变 | 键名是内部标识；bundle id 变了，域本身是新的，只需从旧域搬值 |
| Sparkle feed | `osaurus-ai.github.io/…` | `https://nuo.app/appcast.xml` | 自动检查关闭，等 feed 真发布 |
| DMG / 产物 | `Osaurus-<v>.dmg` | `Nuo-<v>.dmg` | `build-and-release.yml` |

---

## 5. 冻结清单（摘要）

完整表格与取证命令见 `docs/brand/INTERNAL-IDENTIFIERS.md`。原则：**用户看不见，或者改了只会碎的东西，一律不碰。**

- Swift 模块 / 包 / target：`OsaurusCore`、`OsaurusCLI`、`OsaurusCLICore`、`OsaurusRepository`、`OsaurusNetworking`、`OsaurusPlugins`、`OsaurusPluginTestKit`、`OsaurusEvals`、`OsaurusEvalsKit`、`OsaurusAI`。
- 插件 ABI：`osaurus_plugin_entry_v2`、`osr_*` 符号与类型、插件 bundle 清单 `osaurus-bundle.json`。
- 工具与协议：`osaurus_help` / `osaurus_inspect` / `osaurus_config`、`mcp__osaurus__*`、`X-Osaurus-*` 头、`window.__osaurus`、`__osaurus_abi_probe__`。
- 环境变量：`OSAURUS_*`、`OSU_*`。
- 系统标识：日志 subsystem `ai.osaurus`、dispatch label、`group.com.osaurus.shared`、`ai.osaurus.*` defaults 键、`ai.osaurus.id`、`osk-v1.`、加密域分隔串。
- 网络服务：`github.com/osaurus-ai/vmlx-swift` 等上游仓库地址、`www.osaurus.ai` API 域名。
- 工程与产物：目录名、工程/工作区文件名、scheme 名 `osaurus`、`osaurus-cli`、`osaurus-plugin-host`、`osaurus-evals`、CI artifact 内部名、Sentry release 名。
- 证据：`docs/evidence/**`、`results/**`、`reports/**`。

---

## 6. 架构：brand 层

```
scripts/brand/
  brand.json          唯一真源：新旧名字、冻结字面量、路径分类
  rules/10-app-identity.json    Phase 1：产物名、bundle id、Info.plist 与它的 6 语言本地化
  rules/11-artifact-chain.json  Phase 1：签名 / 打包 / dSYM / Sentry / appcast 链路
  rules/12-cli-surface.json     Phase 1：CLI 命令名、help 文案、安装软链
  rules/13-runtime-surfaces.json Phase 3：Info.plist 基础文案、内置 CLI 安装卡片、
                                Claude Code helper、Release 脚本、模板/Issue/WhatsApp 设备名
  rules/20-runtime.json         Phase 2（待加）
  rules/30-ui-text.json         Phase 3：Localizable.xcstrings key/value（xcstrings op）+ Swift key 引用同步
  rules/40-docs.json            Phase 5：内置指南语料（产品名 / 数据根 / CLI 与 MCP 命令 / 冠词 / 安装指令）
  brand.py            引擎：apply / verify / snapshot / inventory
  apply.sh            重放（每次 upstream merge 后跑）
  verify.sh           CI 守卫（<1s）
  snapshot.sh         重测棘轮基线
  baseline.json       当前遗留计数（用户可见口径）
```

### 6.1 规则引擎

四种 op：

| op | 用途 | 幂等保证 |
|---|---|---|
| `replace` | 正则替换（可限定文件、可只改 Swift 字符串字面量） | 替换结果再匹配不到原式 |
| `pbx-setting` | 按 bundle id 定位 `buildSettings` 块后改/删单个 build setting | 目标值已正确则跳过 |
| `insert-after` | 在锚点字面量后插入一行（plist 数组项） | 插入内容已存在则跳过 |
| `block` | 锚定多行原文的整块替换（脚本逻辑补丁） | 锚点消失且替换内容已在则跳过；两者都不在 → 退出码 3 报冲突 |

`block` 的两个修饰：

- `raw: true`：锚点与替换内容不做 `{placeholder}` 替换。Shell 里满屏 `${VAR}`/`${arr[@]}`，不豁免会被占位符表判成未知占位符。
- `template: scripts/brand/templates/…`：替换内容从独立文件读，不写进 JSON。fork 自有的整文件脚本（`scripts/osaurus`、`scripts/release/install_cli_symlink.sh`）用这个形式：模板可正常 diff/编辑，`find` 仍是上游原文，上游改了这个文件就 exit 3。

设计要点：

- **不做 before-count 断言，只做 post-condition（0 匹配）**。上游 merge 把某行带回来，规则自然重新命中；merge 带来新写法，规则立刻失效可见。
- **冻结字面量先切割**：任何文本规则执行前，先把 `brand.json → frozen.literals` 里的标识符切成不可编辑片段，所以一条 `Osaurus → Nuo` 的粗规则也碰不到 `OsaurusCore`、`ai.osaurus.`、`X-Osaurus-*`。
- **Swift 只数/只改字符串字面量**：`import OsaurusCore`、`OsaurusPaths.root()` 是代码不是品牌面，永不参与计数与改写。
- **`block` 规则先于 `replace` 执行**：整块补丁锚定今天的原文，细粒度替换随后处理剩下的部分。
- **`enforced` 分阶段开启**：阶段没做完时规则存在但不阻塞 CI；阶段落地时翻成 `true`，从此 CI 保证不再回退。

### 6.2 守卫（`brand-guard`）

三道检查，任何一条失败 CI 红：

1. **规则吸收**：所有 `enforced: true` 的规则必须 0 匹配。
2. **棘轮**：`paths.strict`（已改造面）里的文件，遗留计数不得超过 `baseline.json`；新增遗留直接失败。缩小不失败，但会提示重测基线。
   还没改造的面放在 `paths.strict_pending`，只统计不拦截 —— 每个阶段落地时把对应 glob 从 pending 挪到 strict，闸门跟着阶段走，不会一上来就红。
3. **契约存在**：`frozen.contracts` 里的字符串必须仍在（例如 `import OsaurusCore` ≥ 1200 次、`osaurus_plugin_entry_v2` 存在）。上游合进来把插件 ABI 弄丢会立刻被抓到。

当前实测（2026-11-04）：strict 51 个文件 / 864 处遗留，pending 50 个文件 / 285 处，79 条规则全部 `enforced`，`verify.sh` 约 3.6s。本轮把 `Packages/OsaurusRepository/**`、`helpers/**`、`Resources/Templates/**`、`.github/ISSUE_TEMPLATE/**` 纳入 strict，并给规则引擎加了文件读取与 Swift 字面量切片缓存（否则守卫约 8–9s）。

> `scripts/live-proof/**`、`docs/evidence/**`、`results/**`、`reports/**` 是对历史证据的归档，不参与棘轮 —— 改写已归档的证明等于伪造证据。

### 6.3 与上游合并的工作流

```bash
git fetch upstream && git merge upstream/main      # 正常解冲突
scripts/brand/apply.sh                             # 重放规则
scripts/brand/verify.sh                            # 守卫
scripts/brand/snapshot.sh --write                  # 阶段推进后重测基线
```

规则锚点被上游改掉时 `apply.sh` 以退出码 3 中止并打印期望原文 —— 这是**设计好的失败**，不是静默放过。处理流程见 `docs/brand/UPSTREAM-SYNC.md`。

---

## 7. 阶段计划

### Phase 0 — brand 层（已完成）

- `scripts/brand/brand.json`、`rules/10-app-identity.json`、`brand.py`、`apply.sh`、`verify.sh`、`snapshot.sh`、`baseline.json`。
- `docs/brand/`：本方案、冻结清单、上游同步 Runbook。
- `.github/workflows/ci.yml` 增加 `brand-guard` job。
- `AGENTS.md` 增加一条硬规则引用。
- 验收：`apply.sh` 对当前树实际产生 65 处变更、再跑一次 0 处（幂等）、`verify.sh` 退出 0 且 <1s；人为往 `Makefile` 写一行 `Osaurus` 后 `verify.sh` 退出 1；把任一规则翻成 `enforced: true` 后 `verify.sh` 退出 1。三条均已实测。

### Phase 1 — 身份与产物（已落地，2026-11-04 完成编译验收；记录见下方 Phase 2 状态行）

范围（`rules/10-app-identity.json` + `11-artifact-chain.json` + `12-cli-surface.json` + 手写补丁）：

- pbxproj：`PRODUCT_NAME = Nuo`、3 个 bundle id、`TEST_HOST`、`CFBundleDisplayName`、`SU_FEED_URL`、`SUEnableAutomaticChecks = NO`；删除 `INFOPLIST_KEY_NSMicrophoneUsageDescription`（见 7.1）。
- `App/osaurus/InfoPlist.xcstrings`：13 个产品相关的 key × 6 语言（`CFBundleDisplayName`、`CFBundleName`、11 条权限文案；`NSHumanReadableCopyright` 留空）。**这是最容易漏的一处**——Xcode 把它编译成 `<lang>.lproj/InfoPlist.strings`，运行时盖掉 Info.plist，所以 pbxproj 改名后 Dock / Cmd-Tab / Finder / TCC 弹窗仍然显示 Osaurus。规则 `info-plist-l10n.display-name` + `info-plist-l10n.bundle-name`，文件已从 `strict_pending` 挪进 `strict`，遗留计数棘轮在 0。
- 基础 `App/osaurus/Info.plist` 的 11 条权限文案：规则 `13-runtime-surfaces.json → plist.base-permission-copy`。6 种语言之外的系统语言没有 `InfoPlist.strings`，会回退到基础文案；只改 xcstrings 会在这里漏名。同时补上 `NSRemindersFullAccessUsageDescription` 缺失的 5 个翻译（此前只有 `en`，其他语言也会回退）。
- xcscheme：3 处 `BuildableName = "Nuo.app"`。
- `Makefile`、`scripts/build/build_arm64.sh`：产物路径 `Nuo.app`，内嵌 helper 改名 `nuo` 并留 `osaurus` 相对软链。
- `.github/workflows/build-and-release.yml`、`deploy-appcast.yml`：产物名与 artifact 名。
- 手写补丁：`scripts/osaurus` → `nuo` 逻辑（bundle id 双查、候选路径双列），`scripts/release/install_cli_symlink.sh`（装 `nuo`，旧 `osaurus` 软链只在不存在时补），CLI help 文案。

验收：

```bash
make cli && make app
xcodebuild -workspace osaurus.xcworkspace -scheme osaurus -configuration Debug \
  -derivedDataPath build/DerivedData build | tail -5
ls build/DerivedData/Build/Products/Debug/Nuo.app/Contents/Helpers   # nuo + osaurus 软链
xcodebuild -workspace osaurus.xcworkspace -scheme OsaurusCoreTests test  # 既有套件不回归
```

> 本机构建前置：Xcode 27 需要单独下载 Metal 工具链（`xcodebuild -downloadComponent MetalToolchain`）；没有 Developer ID 证书时加 `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` 做未签名编译验收。`Nuo.app` 的沙箱内核来自 `scripts/build/fetch_sandbox_kernel.sh`，需下载约 696MB 的 Kata Release 资源。

### Phase 2 — 运行时身份与数据迁移

**状态：源码层已落地（2026-11-01）。2026-11-04 用 Xcode 27.2 验收：`make cli` 通过；`make app` 编译出 `Nuo.app`（`CFBundleIdentifier com.nuo.app`、`Contents/Helpers/nuo` + `osaurus` 软链、`osaurus-plugin-host` 齐全，`nuo version` 输出 `Nuo 1.0 (1)`），只差 Kata 沙箱内核（696MB GitHub Release 资源，代理下约 36KB/s）未下载；`OsaurusRepository` 111 个单测通过。`OsaurusCoreTests` 在本机卡在 `SecItemCopyMatching`（Keychain 读取，测试环境问题，不是品牌改动）。**

**本机（无 Xcode，仅 CLT）已做的替代验证（2026-11-01）**：

- `swift build --package-path Packages/OsaurusRepository` **通过**（含 `Brand.swift`、`ToolsPaths.swift` 真编译）。
- `swift build --package-path Packages/OsaurusCLI` **通过**。过程中抓到并修复一个真 bug：`InstallationDiagnostics.swift` 用 `Brand.Legacy.dataRootName` 但漏 `import OsaurusRepository`。
- OsaurusCore 全部 21 个 Phase 2 改动文件用 SwiftPM 生成的 frontend 命令改 `-typecheck` 重放，**0 error**（整条模块级类型检查，不是逐文件 parse）。
- 仍然做不到、必须等 Xcode 的：含 `@State` 的 SwiftUI 批次（CLT 无 `SwiftUIMacros` 插件）、`actool`/`xcstringstool` 资源编译、`swift test`（CLT 无 XCTest）。`vmlx-swift` checkout 里有一个本地排除 `.metal` 的补丁（`swift package update` 即还原，不进入仓库）。
- 本地 hack 已全部还原：`Packages/OsaurusCore/Package.swift` 恢复原样，无遗留 stub 文件。

运行时真源是 `Packages/OsaurusRepository/Brand.swift`：app（`OsaurusCore`）与 CLI（`OsaurusCLICore`）唯一共同依赖的包，所以常量只写一份，不新建包（避免 pbxproj / `Package.swift` churn）。

```swift
public enum Brand {                      // 用户可见身份
    static let display = "Nuo"
    static let slug = "nuo"
    static let bundleID = "com.nuo.app"
    static let urlScheme = "nuo"
    static let urlSchemes: Set<String>   // nuo + osaurus（兼容期双解析）
    static let dataRootName = ".nuo"
    static let bonjourServiceTypes = ["_nuo._tcp", "_nuo-mobile._tcp"]
    static let controlNotificationPrefix = "com.nuo.control"
    static let defaultsDomain = bundleID
    enum Keychain { static let all: [KeychainService] }   // current + legacy 成对
    enum Legacy {                        // 只给升级读取用，谁都不许往里写
        static let display/slug/bundleID/urlScheme/dataRootName
        static let appSupportDirectoryName = "com.dinoki.osaurus"
        static let bonjourServiceTypes = ["_osaurus._tcp", "_osaurus-mobile._tcp"]
        static let controlNotificationPrefix = "com.dinoki.osaurus.control"
        static let defaultsDomain = bundleID
    }
}
```

改动点（均已落地）：

1. 数据根：`OsaurusPaths.defaultRoot` → `~/.nuo`，复用上游既有的 `migrateLegacyApplicationSupportRootIfNeeded` 走两跳（App Support → `~/.osaurus` → `~/.nuo`），新增 `clonefile` 快路径（APFS COW，模型几十 GB 也不拷数据）。CLI 侧 `ToolsPaths.root()` 在 `~/.nuo` 不存在时回退读 `~/.osaurus`，所以 CLI 先于 app 启动也看得到数据。
2. Keychain：14 个 service 名换成 `com.nuo.*` / `ai.nuo.*`，采用**懒迁移**（read-through）而不是启动全量扫描：读新名 → `.notFound` 才读旧名 → 命中则 best-effort 前向复制。旧名读到的 `unavailable` / `accessDenied` **原样返回**，绝不降级成 `notFound`（`StorageKeyManager` 会把 `notFound` 当成"没有 DEK"从而铸新密钥覆盖已加密数据）。`MasterKey` 只读旧名、不前向复制（master key 是身份/ACL 根，改由新身份写入新名）。`ai.osaurus.id` 冻结不改。
3. Bonjour：advertiser 以**旧类型为 primary** 保留 publish/retry 状态机，新类型作为无 delegate 的静默 companion 双注册；browser 同时浏览两种类型，按 agent id 去重，只有两种公告都消失才走 12s 宽限期下线。
4. URL scheme：Info.plist 双注册；解析统一走 `Brand.ownsURLScheme(_:)`（`AppDelegate`、`PairingDeepLinkRouter`、`WorkspacesDeepLinkRouter`、`ThemesDeepLinkRouter`、`ThemeShareService`、`ThemeLibraryManagementService`、`HuggingFaceModelDeepLink`、公告 CTA）；新链接（邀请、主题分享、workspaces 归一化）一律生成 `nuo://`。签名 payload（`osaurus-agent-invite-v1:`）不动，否则旧邀请全部验签失败。
5. 分布式通知：`com.nuo.control.*` 新发 + `com.dinoki.osaurus.control.*` 双发一个版本；app 侧 `observeControlAction` 同时观察两个名字。
6. 迁移不在单独的 `BrandMigration.swift`：数据根复用 `OsaurusPaths` 的一次性迁移，Keychain 用读穿迁移，两者都以"旧数据整版保留"为前提。
7. CLI 侧 app defaults 域名跟随：`com.nuo.app` 优先、`com.dinoki.osaurus` 兜底（一个版本）。
8. `StorageLocationStandards` 不再声称"迁移未决"：它照实报告 `~/.nuo` 是 home dot-directory、`~/.osaurus` 与 App Support 旧根是否还在、各自的一次性 marker 是否已写。

验收：迁移证明（旧目录/旧 defaults/旧 keychain 造数据 → 新装启动 → 数据齐、旧数据仍在）、双注册证明（`open osaurus://…` 仍可达、`dns-sd -B _nuo._tcp` 与 `_osaurus._tcp` 都能看到）、测试隔离证明（`OSAURUS_TEST_ROOT` 下不触发迁移）。

### Phase 3 — 界面与文案

**状态：Localizable.xcstrings A/C 类机械替换已落地（2026-11-01）；Swift 字面量与运行时可见面已落地（2026-11-04）；Dino 隐喻退役（2026-11-05）**，B 类外部事实（Router / Cloud / ID / osaurus.ai）保留待 `HIDE-UPSTREAM-SERVICES` 一起处理。

2026-11-05 追加：onboarding 的 Dino 隐喻整体退役。规则 `ui-text.onboarding-agent-copy`（英文，驱动 key 改名与 Swift 字面量同步）+ 5 条分语言规则把 17 个 catalog key 与 6 语言译文改写为各语言的 "agent"：德语按 Agent 的 n-Deklination 处理（`deinen Agenten` / `dein Agent`），韩语按元音结尾调整助词（`에이전트가/를`），俄语利用词干替换保留格尾（`динозавр→агент` 自动得到 `агента/агенту/агентом`），简繁中文把量词 `一只小恐龙` 改为 `一个智能体`。`AgentMascot.displayName` 的 6 条无障碍标签由 `ui-text.agent-avatar-accessibility` 改为 `Blue agent` 等。视觉资产（6 个恐龙头像、`osaurus-brain`、`*-create` 插画）仍需美术产出，见 Phase 4。

2026-11-04 补的这一批（规则 `13-runtime-surfaces.json` + 扩展后的 `30-ui-text.json`）：

- 小写 `osaurus` 残留：HTTP 错误里的 CLI 指令（`osaurus status/import/CLI`）、安全模式通知、文件夹授权弹窗、主题导入提示、Workspace 邀请链接示例。
- 运行时诊断：存储设置里的 “Service:” 从 `com.osaurus.storage` 改为实际使用的 `com.nuo.storage`。
- 冠词：`an Nuo` → `a Nuo`（15 处，含 Swift 与 xcstrings）。
- 发布链路：appcast / HF 上传脚本的 `Osaurus-<version>.dmg` 改为 `Nuo-`（原先会 404），Discord 公告改用 `PUBLIC_REPO`，release note 文案。
- 其他：agent 模板作者名、GitHub Issue 模板、WhatsApp 已链接设备名。
- `Packages/OsaurusRepository` 纳入 `ui-text.swift-literals` 与 strict：bundle 风险文案、校验错误、`[Osaurus]` 日志前缀。

已落地（`rules/30-ui-text.json`，新增 `xcstrings` op，见 `brand.py`）：

- 新增 `xcstrings` op：JSON 结构化改 key + stringUnit value（含 variations 嵌套），文本级原位写回保持 Xcode `"key" : value` 格式不变；key 改名后经 `sync_refs` 按整字面量匹配同步 Swift 引用（`sync_refs_exclude` 跳过 3 个外部契约文件）；幂等，verify 按"应改未改"计数。
- **283 个 key 改名**（342 个含 Osaurus key 中 59 个被排除组保护）+ **1007 条 value 替换** + **~320 处 Swift key 引用同步**（127 个 Swift 文件）。
- C 类数据根：值与 key 中的 `~/.osaurus` → `~/.nuo`（57 处纯路径值 + Swift 硬编码路径文案）。
- 排除组（key 命中即整组多语言跳过，R7 假承诺保护）：`Osaurus Cloud`、`Osaurus Router`、`Osaurus ID`、`OsaurusID`、`Osaurus Identity`、`Osaurus Secure`、`Osaurus Premium`、`Osaurus Connect`、`OsaurusAI`；小写 `osaurus`（插件/配置键/域名）与大写 `OSAURUS`（环境变量）经大小写敏感匹配自然保留。
- `sync_refs_exclude`：`OsaurusCloudMediaClient.swift`（上游 Cloud 媒体 providerName）、`MCPOAuthClientMetadata.swift`（注册到上游的 OAuth clientName）、`OpenRouterOAuthService.swift`（OpenRouter HTTP-Referer/appTitle）。
- 棘轮：`Localizable.xcstrings` 与 `App/osaurus/*.swift` 从 `strict_pending` 挪入 `strict`；2026-11-04 又并入 `Packages/OsaurusRepository/**`、`helpers/**`、`Resources/Templates/**`、`.github/ISSUE_TEMPLATE/**`，基线重测（strict 51 文件 / 864 处，其中大部分是受保护的 B 类与 frozen 标识）。
- 验证：diff 纯洁性（删行全含 legacy、增行全含 Nuo，1364+1364 一一对应）、JSON 合法性（9995 keys 不变）、幂等（二次 apply 为 0）、排除项保留计数、5 语言语序抽查（德/俄/韩/简/繁无语病，"the Nuo agent"/"die Nuo-Sandbox"/"Nuo's" 均合法）。测试文件 hardcode 翻译断言风险已排查（仅 5 处上游 API mock/fixture，正确保留）。

剩余（下一批/人工）：

- 文档面：`README.md`、`COMMUNITY_EVALS.md`、`docs/plugins/**`、`docs/examples/**`——Phase 5（README 需重写，不是替换）。
- 内置指南已完成，见下节 Phase 5 状态；`Guide/**` 已从 `strict_pending` 并入 `strict`。
- 资产：App 图标、托盘图标、wordmark、DMG 背景——Phase 4。
- B 类上游服务文案与入口——`HIDE-UPSTREAM-SERVICES`，与默认开关一起做。
- Codex `profileName = "osaurus"`：UI 文案与 `~/.codex` 默认 profile 名要一起改，影响既有配置。
- `NSRemindersFullAccessUsageDescription` 新补的 5 个翻译需要母语者过一遍（其他权限条目的既有翻译仍是旧句式，属于上游翻译滞后，不在本轮范围）。

B 类人工清单（保留计数见 baseline）：

| 项 | 性质 |
|---|---|
| Osaurus Cloud（~60 值） | 上游云服务，Nuo 无对应物 |
| Osaurus Router（~92 值） | 上游路由/中继 + 计费 |
| Osaurus ID / Identity（~27 值） | 上游身份服务（`ai.osaurus.id` 令牌已冻结） |
| OsaurusAI（40 值 + Swift 字面量） | Hugging Face org / 模型 id 前缀（frozen） |
| osaurus.ai / agent.osaurus.ai（12 值） | 上游域名 |
| OSAURUS_*（16 值） | 环境变量 frozen 文案 |
| model_providers.osaurus（6 值） | Codex config 键名 frozen |
| osaurus.messages（12 值） | 旧插件 bundle id frozen |
| osaurus.config.toml（6 值） | Codex profile 文件名——改文案需同步决策 profileName 默认值 |
| 3 个 sync_refs_exclude Swift 文件 | 上游 OAuth / OpenRouter / Cloud provider 外部契约 |

- `App/osaurus/InfoPlist.xcstrings`：**已在 Phase 1 完成**（`info-plist-l10n.*`）；`NSRemindersFullAccessUsageDescription` 的 5 个缺失翻译与 11 条基础 `Info.plist` 文案已在 2026-11-04 补齐。仍建议母语者抽查德/俄/韩/简繁的语序。
- Swift 字面量与运行时可见面（`AppDelegate`、`osaurusApp.swift`、`AppIntents`、CLI help、HTTP 错误、通知、文件授权、主题导入、存储诊断）：**已完成（2026-11-04）**，全部在 enforced 规则里。
- 5 种非英文语言需要抽查：机械替换后检查语序与冠词（德/俄/韩/简繁）——**A/C 类已抽查通过（2026-11-01）**。

### Phase 4 — 资产

**状态（2026-11-05 核对）：主视觉与智能体头像已换，装饰插画未换。**

已落地：`AppIcon.appiconset` 全部 10 个尺寸与 `osaurus-app-icon.icon`（Scheme A 朱文印）、`osaurus.imageset`（几何 N，18/36/54 三档，template）、`osaurus-main.imageset`（深底印章）、`osaurus-logo.imageset`（印芯 template）、`AccentColor.colorset`（`#F8141C`）、`assets/dmg-bg.tiff`（纸底 + 朱红印芯）。

智能体头像（2026-11-05）：

- `osaurus-avatar-{blue,green,orange,purple,red,yellow}` 6 张恐龙已换成同一画风的人物肖像（256/512/768 透明 PNG，底边贴齐）。imageset 目录名与文件名保持不变，`AgentMascot` 与全部 27 个调用点零改动。
- 新增 `nuo-primary-avatar.imageset`：内置 Orchestrator 的肖像。`AgentMascot` 增加 `.primary` case，手写 `allCases` 把它排除在头像选择器、onboarding 头像条与随机之外；`Agent.default.avatar` 由 `"green"` 改为 `"primary"`。
- 生成流程（可复现）：本机 ComfyUI Z-Image Turbo（8 步、cfg 1.0、`res_multistep`、1024²、固定 seed）→ scipy 最大连通域抠图 → 底边贴齐归一化 → 三档导出。无 IPAdapter/ControlNet/LoRA，角色一致性仅靠 prompt + 固定 seed，属于风格统一而非同一角色锁定。

未落地（需美术产出，阻塞"品牌统一"）：
- `osaurus-brain`（`OnboardingConfigureAIView` 使用）。
- `osaurus-{color}-create` 6 张、`osaurus-tool` / `sandbox` / `data` / `built` / `identity` 等装饰插画。
- `osaurus-logo-wordmark.svg` 仍是 `OSAURUS` outline 字标（当前无 Swift 源码引用，仅资源目录）。

- App 图标（`App/osaurus/osaurus-app-icon.icon`）、`Assets.xcassets` 里 24 个品牌图：先出占位（`N` 字标 + 单色托盘图标），等美术。
- `osaurus-logo-wordmark.svg` 是 outline 化路径，只能重画，不能改字。
- 顺手修 `osuarus-yellow-create` 拼写（4 个文件，1 处 Swift 引用）。
- `assets/dmg-bg.tiff`（2.9MB 位图）需视觉核对是否烘焙了 wordmark。

**不重命名 imageset 目录**：Swift 里有 925 行按名字引用，改名纯属自伤；可见品牌在图像内容，不在资源名。

### Phase 5 — 文档

**状态（2026-11-05）：内置指南已落地。** `rules/40-docs.json` 用 6 条规则处理 28 篇语料，共 158 处（产品名 103 + 数据根 25 + CLI 23 + MCP 1 + 冠词 5 + 安装指令 1）：

| 规则 | 内容 |
|---|---|
| `docs.guide-brand` | 产品自称 `Osaurus` → `Nuo`；`(?!\s+(?:Cloud|Router|ID|Identity|Secure|Premium|Connect)\b)` 前瞻把 B 类上游服务留在原样 |
| `docs.guide-data-root` | `~/.osaurus` → `~/.nuo`（Phase 2 已迁移的数据根，指南此前仍指向旧目录） |
| `docs.guide-cli-command` | 反引号内与行首的 `osaurus ui/serve/status/config/mcp/import/tools/version` → `nuo …` |
| `docs.guide-mcp-launch-command` | MCP 宿主示例的 `command: "osaurus"` → `command: "nuo"` |
| `docs.guide-article` | `an Nuo` → `a Nuo`（`Osaurus` 元音开头、`Nuo` 不是） |
| `docs.guide-install-instruction` | 删掉 `` `brew install --cask osaurus` ``：那是上游应用，装上来的不是 Nuo.app |
| — | 未改：`Osaurus Cloud` / `Osaurus Router` 等 B 类，`osaurus_config` / `osaurus_inspect` / `osaurus_help` / `OSAURUS_*` / `ai.osaurus.` / `osaurus.ai` / `OsaurusAI` / `[model_providers.osaurus]` / `codex --profile osaurus` / `@osaurus/n8n-nodes-osaurus`（R7 冻结） |

棘轮：`Guide/**` 从 `strict_pending` 并入 `strict`，基线重测为 **strict 64 文件 / 895 处**（含上述冻结项），`apply.sh` 二次运行 0 变更，`verify.sh` OK。

剩余（人工）：

- `README.md` 重写（不是替换）：badge 指向上游仓库、Discord、X、`docs.osaurus.ai` 全部失效，需要换成 nuo 的或删掉。
- `COMMUNITY_EVALS.md`、`docs/plugins/**`（12 篇）、`Resources/Guide/**`（28 篇）机械替换 + 人工校对链接。
- 其余 `docs/**` 冻结：它们是工程文档，描述的对象仍是 `OsaurusCore` 等模块。

### Phase 6 — 发布链路与证明

- 2026-11-04 已修正脚本层的产物名不一致：appcast 与 HF 上传按 `Nuo-<version>.dmg` 取件（原先 404），Discord 公告改用 `PUBLIC_REPO` 而不是上游仓库，release note 文案改为 Nuo。剩余的是仓库外凭据与实机验证。
- Developer ID 证书、nuo appcast feed、notarization profile（仓库外依赖）。
- 实机 UI 走查 + eval 套件（`make ci-test`、`make evals-deterministic`、AgentLoop 相关 lane）。
- PR 证据按 `AGENTS.md` 的 Release Proof 要求写：源 SHA、模型/套件、原始分数与分母、失败归因、本地证据路径。

---

## 8. 数据迁移设计

### 8.1 触发条件

只在 `OSAURUS_TEST_ROOT` 未设置时执行（否则测试会动真实家目录）。数据根用 `OsaurusPaths` 既有的 `.legacy-application-support-merge.done` 标记（写在**目标根**里，两跳各一份）保证只跑一次、可重入、可诊断；Keychain 用读穿迁移，没有全局标记文件。

### 8.2 五类数据

| 数据 | 位置 | 迁移方式 |
|---|---|---|
| 数据根 | `~/.osaurus` → `~/.nuo` | `cp -cR`（APFS clonefile，模型几十 GB 也是秒级、不占额外空间）；非 APFS 回退 `ditto` |
| 旧 App Support | `~/Library/Application Support/com.dinoki.osaurus` | 现有迁移链继续并入新根（保持两段兼容） |
| UserDefaults | 域 `com.dinoki.osaurus` → `com.nuo.app` | 枚举旧域 key 写进新域；**键名不变**（`ai.osaurus.*` 冻结）。CLI 侧按域名字面量读取（`Pull.swift:183`、`Configuration.swift:98`），必须同步；`group.com.osaurus.shared` 冻结（涉及 App Group entitlement，不改） |
| Keychain | 14 个 service（`ai.osaurus.id` 除外） | 读新名 → `.notFound` 时读旧名 → 命中则 best-effort 前向复制；`unavailable`/`accessDenied` 原样上报 |
| 配置/端口 | `~/.nuo/config/server.json` | 随数据根整体搬迁 |

### 8.3 失败语义

- Keychain 读被 ACL 拒绝（`errSecAuthFailed` / `errSecInteractionNotAllowed`）：错误原样返回给调用方，由既有 UI 路径提示；**绝不降级成 `.notFound`**（否则 `StorageKeyManager` 会铸新 DEK 覆盖已加密数据）。
- 迁移中途失败：标记文件写 `partial`，下次启动重试；旧根从不删除，删掉 `~/.nuo` 即回滚。
- 两边都存在：以新根为准，不合并（避免每次启动重扫）。

### 8.4 回滚

`rm -rf ~/.nuo` + `rm -f ~/Library/Preferences/com.nuo.app.plist`，旧连接管。文档里写清楚。

---

## 9. 并存期（一个版本）

| 面 | 并存方式 | 退场时机 |
|---|---|---|
| URL scheme | `nuo://` + `osaurus://` 双注册 | 下个版本删旧 |
| Bonjour | 双注册 + 双浏览 | 下个版本删旧 |
| CLI | 装 `nuo`，`osaurus` 软链只在缺失时补 | 手动退场 |
| 内嵌 helper | `nuo` + `osaurus` 相对软链 | 下个版本 |
| 通知 | 新旧双发 | 下个版本 |
| 旧数据 | 整版保留 | 用户自己删 |

---

## 10. 风险登记

| # | 风险 | 影响 | 缓解 |
|---|---|---|---|
| R1 | bundle id 变更后 Keychain ACL 视为另一 app，读旧条目弹窗或被拒 | 密钥看似"消失" | 读旧写新 + 显式失败 UI + 退化方案（冻结 14 个 service 名，`ai.osaurus.id` 本来就不动） |
| R2 | TCC 权限全部重弹（麦克风/通讯录/日历/位置/屏幕录制/自动化） | 首启体验 | 已知行为，文案里说明；不假装保留 |
| R3 | 新旧 App 同时存在抢 1337 端口 | 服务起不来 | 旧 App 提示退出；新 App 端口冲突时明确报错而非静默换端口 |
| R4 | Sparkle feed 不存在 | 手动检查更新失败 | 自动检查关闭；菜单项在 feed 未配置时隐藏 |
| R5 | 5 种非英文语言机械替换后语义走样 | 界面不专业 | Phase 3 抽查 + 关键页面人工过一遍 |
| R6 | 上游 merge 改掉规则锚点 | apply 中止 | 退出码 3 + 打印期望原文 + Runbook |
| R7 | `osaurus.ai` 相关文案（Cloud 定价、Discord、文档站）机械替换后变成假承诺 | 用户被误导 | B 类文案逐条人工改写，禁止机械替换 |
| R8 | 发布链路（证书 / notarize / feed）在仓库外 | Phase 6 卡住 | 提前并行准备，不阻塞 Phase 1–5 |
| R9 | 迁移时模型目录几十 GB | 首启卡死 | APFS clonefile，失败回退 ditto 并显示进度 |
| R10 | 旧登录项变孤儿 | 开机启动失效 | 新 App 首启重新注册；文档说明 |

---

## 11. 验证矩阵

| 层 | 命令 / 证据 | 门 |
|---|---|---|
| 品牌守卫 | `scripts/brand/verify.sh` | 必须 <5s、退出 0 |
| 编译 | `make cli`、`make app` | 0 error |
| 单测 | `make test`、`make ci-test` | 不回归基线 |
| 发布构建 | `scripts/build/build_arm64.sh`（本地未签名变体） | `Nuo.app` 产物 + helper 软链 |
| 迁移 | 造旧数据 → 首启 → 比对会话/模型/密钥 | 三类数据齐全，旧数据仍在 |
| 并存 | `open osaurus://…`、`dns-sd -B _osaurus._tcp` | 双向可达 |
| 实机 UI | 菜单栏、关于、设置、6 语言切换 | 无 `Osaurus` 残留 |
| Eval | `make evals-deterministic` + AgentLoop lane | 按 `AGENTS.md` 记录原始分数 |

---

## 12. 工作量与推进顺序

| 阶段 | 文件量 | 依赖 | 可并行 |
|---|---|---|---|
| Phase 0 | 8 | — | 已完成 |
| Phase 1 | ~26 | Phase 0 | 与 Phase 2 文件集不相交，可并行 |
| Phase 2 | ~20 + 1 新模块 | Phase 1（产物名） | 与 Phase 1 并行 |
| Phase 3 | ~10 源文件 + 2 xcstrings | Phase 1 | 否（依赖产物名验证） |
| Phase 4 | ~30 资产 | 美术输入 | 与 Phase 3 并行 |
| Phase 5 | ~42 文档 | Phase 3 | 是 |
| Phase 6 | CI/发布 | 证书 + feed | 最后 |

---

## 13. 待外部输入

1. **美术**：wordmark（outline 矢量）、app 图标、托盘图标、占位字标确认。
2. **域名与证书**：`nuo.app` 是否自有（决定 bundle id 终值）、Developer ID、notarization profile。
3. **appcast feed**：`https://nuo.app/appcast.xml` 的托管方式。
4. **版权行**：`LICENSE` / `Credits.rtf` / `NSHumanReadableCopyright` 的最终署名。
